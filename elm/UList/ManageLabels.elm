module UList.ManageLabels exposing (main)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Browser
import Task
import Browser.Navigation exposing (reload)
import Json.Encode as JE
import Lib.Html exposing (..)
import Lib.Util exposing (..)
import Lib.Api as Api
import Lib.Ffi as Ffi
import Gen.Api as GApi
import Gen.UListManageLabels as GML


main : Program GML.Send Model Msg
main = Browser.element
  { init   = \e -> (init e, Cmd.none)
  , view   = view
  , update = update
  , subscriptions = always Sub.none
  }

type alias Model =
  { uid     : String
  , state   : Api.State
  , labels  : List GML.SendLabels
  , editing : Maybe Int
  }

init : GML.Send -> Model
init d =
  { uid     = d.uid
  , state   = Api.Normal
  , labels  = List.filter (\l -> l.id >= 0) d.labels
  , editing = Nothing
  }

type Msg
  = Noop
  | Private Int Bool
  | Label Int String
  | Delete Int (Maybe Int)
  | Add
  | Submit
  | Submitted GApi.Response


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    Noop -> (model, Cmd.none)
    Private n b -> ({ model | labels = modidx n (\l -> { l | private = b }) model.labels }, Cmd.none)
    Label n s   -> ({ model | labels = modidx n (\l -> { l | label   = s }) model.labels }, Cmd.none)
    Delete n o  -> ({ model | labels = List.filter (\l -> l.id > 0 || l.delete == Nothing) <| modidx n (\l -> { l | delete = o }) model.labels }, Cmd.none)
    Add ->
      ( { model | labels = model.labels ++ [{ id = -1, label = "New label", private = List.all (\il -> il.private) model.labels, count = 0, delete = Nothing }] }
      , Task.attempt (always Noop) <| Ffi.elemCall "select" <| "label_txt_" ++ String.fromInt (List.length model.labels) )

    Submit -> ({ model | state = Api.Loading }, GML.send { uid = model.uid, labels = model.labels } Submitted)
    Submitted GApi.Success -> (model, reload)
    Submitted r -> ({ model | state = Api.Error r }, Cmd.none)


view : Model -> Html Msg
view model =
  let
    item n l =
      tr [ class "compact" ]
      [ td [] [ text <| if l.count == 0 then "" else String.fromInt l.count ]
      , td [ class "stealth" ]
        [ if l.id > 0 && l.id < 10 then text l.label
          else inputText ("label_txt_"++String.fromInt n) l.label (Label n) GML.valLabelsLabel
        ]
      , td [ ] [ linkRadio l.private (Private n) [ text "private" ] ]
      , td [ class "stealth" ]
        [      if l.id == 7             then b [ class "grayedout" ] [ text "applied when you vote" ]
          else if l.id > 0 && l.id < 10 then b [ class "grayedout" ] [ text "built-in" ]
          else if l.delete == Nothing   then a [ onClick (Delete n (Just 1)) ] [ text "remove" ]
          else inputSelect "" l.delete (Delete n) []
            [ (Nothing, "Keep label")
            , (Just 1,  "Delete label but keep VNs in my list")
            , (Just 2,  "Delete label and VNs with only this label")
            , (Just 3,  "Delete label and all VNs with this label")
            ]
        ]
      ]

    hasDup = hasDuplicates <| List.map (\l -> l.label) model.labels
  in
    Html.form [ onSubmit Submit, class "managelabels hidden" ]
    [ div [ ]
      [ b [] [ text "How to use labels" ]
      , ul []
        [ li [] [ text "You can assign multiple labels to a visual novel" ]
        , li [] [ text "You can create custom labels or just use the built-in labels" ]
        , li [] [ text "Private labels will not be visible to other users" ]
        , li [] [ text "Your vote and notes will be public when at least one non-private label has been assigned to the visual novel" ]
        ]
      ]
    , table [ class "stripe" ] <|
      [ thead [] [ tr []
        [ td [] [ text "VNs" ]
        , td [] [ text "Label" ]
        , td [] [ text "Private" ]
        , td [] [ ]
        ] ]
      , tfoot []
        [ if List.any (\l -> l.id == 7 && l.private) model.labels && List.any (\l -> not l.private) model.labels
          then tr [] [ td [ colspan 4 ]
            [ b [ class "standout" ] [ text "WARNING: " ]
            , text "Your vote is still public if you assign a non-private label to the visual novel."
            ] ]
          else text ""
        , tr []
          [ td [] []
          , td [ colspan 3 ]
            [ if List.length model.labels < 500 then inputButton "New label" Add [] else text ""
            , submitButton "Save changes" model.state (not hasDup)
            ]
          ]
        ]
      , tbody [] <| List.indexedMap item model.labels
      ]
    ]
