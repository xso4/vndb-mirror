module Reviews.Edit exposing (main)

import Html exposing (..)
import Html.Attributes exposing (..)
import Browser
import Browser.Navigation exposing (load)
import Lib.Html exposing (..)
import Lib.TextPreview as TP
import Lib.Api as Api
import Lib.Util exposing (..)
import Lib.RDate as RDate
import Gen.Api as GApi
import Gen.ReviewsEdit as GRE
import Gen.ReviewsDelete as GRD


main : Program GRE.Recv Model Msg
main = Browser.element
  { init   = \e -> (init e, Cmd.none)
  , view   = view
  , update = update
  , subscriptions = always Sub.none
  }


type alias Model =
  { state       : Api.State
  , id          : Maybe String
  , vid         : String
  , vntitle     : String
  , rid         : Maybe String
  , spoiler     : Bool
  , locked      : Bool
  , isfull      : Bool
  , text        : TP.Model
  , releases    : List GRE.RecvReleases
  , delete      : Bool
  , delState    : Api.State
  , mod         : Bool
  }


init : GRE.Recv -> Model
init d =
  { state       = Api.Normal
  , id          = d.id
  , vid         = d.vid
  , vntitle     = d.vntitle
  , rid         = d.rid
  , spoiler     = d.spoiler
  , locked      = d.locked
  , isfull      = d.isfull
  , text        = TP.bbcode d.text
  , releases    = d.releases
  , delete      = False
  , delState    = Api.Normal
  , mod         = d.mod
  }


encode : Model -> GRE.Send
encode m =
  { id          = m.id
  , vid         = m.vid
  , rid         = m.rid
  , spoiler     = m.spoiler
  , locked      = m.locked
  , isfull      = m.isfull
  , text        = m.text.data
  }


type Msg
  = Release (Maybe String)
  | Full Bool
  | Spoiler Bool
  | Locked Bool
  | Text TP.Msg
  | Submit
  | Submitted GApi.Response
  | Delete Bool
  | DoDelete
  | Deleted GApi.Response


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    Release i  -> ({ model | rid      = i }, Cmd.none)
    Full b     -> ({ model | isfull   = b }, Cmd.none)
    Spoiler b  -> ({ model | spoiler  = b }, Cmd.none)
    Locked b   -> ({ model | locked   = b }, Cmd.none)
    Text m     -> let (nm,nc) = TP.update m model.text in ({ model | text = nm }, Cmd.map Text nc)

    Submit -> ({ model | state = Api.Loading }, GRE.send (encode model) Submitted)
    Submitted (GApi.Redirect s) -> (model, load s)
    Submitted r -> ({ model | state = Api.Error r }, Cmd.none)

    Delete b   -> ({ model | delete   = b }, Cmd.none)
    DoDelete -> ({ model | delState = Api.Loading }, GRD.send ({ id = Maybe.withDefault "" model.id }) Deleted)
    Deleted GApi.Success -> (model, load <| "/" ++ model.vid)
    Deleted r -> ({ model | delState = Api.Error r }, Cmd.none)


showrel r = "[" ++ (RDate.format (RDate.expand r.released)) ++ " " ++ (String.join "," r.lang) ++ "] " ++ r.title ++ " (" ++ r.id ++ ")"

view : Model -> Html Msg
view model =
  let minChars = if model.isfull then   1000 else 200
      maxChars = if model.isfull then 100000 else 800
      len      = String.length model.text.data
  in
  form_ "" Submit (model.state == Api.Loading)
  [ div [ class "mainbox" ]
    [ h1 [] [ text <| if model.id == Nothing then "Submit a review" else "Edit review" ]
    , p [] [ b [] [ text "Rules" ] ]
    , ul []
      [ li [] [ text "Submit only reviews you have written yourself!" ]
      , li [] [ text "Reviews must be in English." ]
      , li [] [ text "Try to be as objective as possible." ]
      , li [] [ text "If you have published the review elsewhere (e.g. a personal blog), feel free to include a link at the end of the review. Formatting tip: ", em [] [ text "[Originally published at <link>]" ] ]
      , li [] [ text "Your vote (if any) will be displayed alongside the review, even if you have marked your list as private." ]
      ]
    , br [] []
    ]
  , div [ class "mainbox" ]
    [ table [ class "formtable" ]
      [ formField "Subject" [ a [ href <| "/"++model.vid ] [ text model.vntitle ] ]
      , formField ""
        [ inputSelect "" model.rid Release [style "width" "500px" ] <|
          (Nothing, "No release selected")
          :: List.map (\r -> (Just r.id, showrel r)) model.releases
          ++ if model.rid == Nothing || List.any (\r -> Just r.id == model.rid) model.releases then [] else [(model.rid, "Deleted or moved release: r"++Maybe.withDefault "" model.rid)]
        , br [] []
        , text "You do not have to select a release, but indicating which release your review is based on gives more context."
        ]
      , tr [ class "newpart" ] [ td [ colspan 2 ] [ text "" ] ]
      , formField "Review type"
        [ label [] [ inputRadio "type" (model.isfull == False) (\_ -> Full False), b [] [ text " Mini review" ]
        , text <| " - Recommendation-style, maximum 800 characters." ]
        , br [] []
        , label [] [ inputRadio "type" (model.isfull == True ) (\_ -> Full True ), b [] [ text " Full review" ]
        , text " - Longer, more detailed." ]
        , br [] []
        , b [ class "grayedout" ] [ text "You can always switch between review types later." ]
        ]
      , tr [ class "newpart" ] [ td [ colspan 2 ] [ text "" ] ]
      , formField ""
        [ label [] [ inputCheck "" model.spoiler Spoiler, text " This review contains spoilers." ]
        , br [] []
        , b [ class "grayedout" ] [ text "You do not have to check this option if all spoilers in your review are marked with [spoiler] tags." ]
        ]
      , if not model.mod then text "" else
        formField "" [ label [] [ inputCheck "" model.locked Locked, text " Locked for commenting." ] ]
      , tr [ class "newpart" ] [ td [ colspan 2 ] [ text "" ] ]
      , formField "text::Review"
        [ TP.view "sum" model.text Text 700 ([rows (if model.isfull then 30 else 10), cols 50] ++ GRE.valText)
          [ a [ href "/d9#3" ] [ text "BBCode formatting supported" ] ]
        , div [ style "width" "700px", style "text-align" "right" ] <|
          let num c s = if c then b [ class " standout" ] [ text s ] else text s
          in
          [ num (len < minChars) (String.fromInt minChars)
          , text " / "
          , b [] [ text (String.fromInt len) ]
          , text " / "
          , num (len > maxChars) (if model.isfull then "∞" else String.fromInt maxChars)
          ]
        ]
      ]
    ]
  , div [ class "mainbox" ]
    [ fieldset [ class "submit" ]
      [ submitButton "Submit" model.state (len <= maxChars && len >= minChars)
      ]
    ]
  , if model.id == Nothing then text "" else
    div [ class "mainbox" ]
    [ h1 [] [ text "Delete review" ]
    , table [ class "formtable" ] [ formField ""
      [ label [] [ inputCheck "" model.delete Delete, text " Delete this review." ]
      , if not model.delete then text "" else span []
        [ br [] []
        , b [ class "standout" ] [ text "WARNING:" ]
        , text " Deleting this review is a permanent action and can not be reverted!"
        , br [] []
        , br [] []
        , inputButton "Confirm delete" DoDelete []
        , case model.delState of
            Api.Loading -> span [ class "spinner" ] []
            Api.Error e -> b [ class "standout" ] [ text <| Api.showResponse e ]
            Api.Normal  -> text ""
        ]
      ] ]
    ]
  ]
