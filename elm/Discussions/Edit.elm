module Discussions.Edit exposing (main)

import Html exposing (..)
import Html.Attributes exposing (..)
import Browser
import Browser.Navigation exposing (load)
import Lib.Html exposing (..)
import Lib.TextPreview as TP
import Lib.Api as Api
import Lib.Util exposing (..)
import Lib.Autocomplete as A
import Gen.Api as GApi
import Gen.Types exposing (boardTypes)
import Gen.DiscussionsEdit as GDE


main : Program GDE.Recv Model Msg
main = Browser.element
  { init   = \e -> (init e, Cmd.none)
  , view   = view
  , update = update
  , subscriptions = always Sub.none
  }


type alias Model =
  { state       : Api.State
  , tid         : Maybe String
  , can_mod     : Bool
  , can_private : Bool
  , locked      : Bool
  , hidden      : Bool
  , private     : Bool
  , nolastmod   : Bool
  , delete      : Bool
  , title       : Maybe String
  , boards      : Maybe (List GDE.SendBoards)
  , boardAdd    : A.Model GApi.ApiBoardResult
  , msg         : TP.Model
  , poll        : Maybe GDE.SendPoll
  , pollEnabled : Bool
  , pollEdit    : Bool
  }


init : GDE.Recv -> Model
init d =
  { state       = Api.Normal
  , can_mod     = d.can_mod
  , can_private = d.can_private
  , tid         = d.tid
  , locked      = d.locked
  , hidden      = d.hidden
  , private     = d.private
  , nolastmod   = False
  , delete      = False
  , title       = d.title
  , boards      = d.boards
  , boardAdd    = A.init ""
  , msg         = TP.bbcode d.msg
  , poll        = d.poll
  , pollEnabled = isJust d.poll
  , pollEdit    = isJust d.poll
  }


searchConfig : A.Config Msg GApi.ApiBoardResult
searchConfig = { wrap = BoardSearch, id = "boardadd", source = A.boardSource }


encode : Model -> GDE.Send
encode m =
  { tid       = m.tid
  , locked    = m.locked
  , hidden    = m.hidden
  , private   = m.private
  , nolastmod = m.nolastmod
  , delete    = m.delete
  , boards    = m.boards
  , poll      = if m.pollEnabled then m.poll else Nothing
  , title     = m.title
  , msg       = m.msg.data
  }


numPollOptions : Model -> Int
numPollOptions model = Maybe.withDefault 0 (Maybe.map (\o -> List.length o.options) model.poll)

dupBoards : Model -> Bool
dupBoards model = hasDuplicates (List.map (\b -> (b.btype, Maybe.withDefault "" b.iid)) (Maybe.withDefault [] model.boards))

isValid : Model -> Bool
isValid model = not (model.boards == Just [] || dupBoards model || Maybe.map (\p -> p.max_options < 1 || p.max_options > numPollOptions model) model.poll == Just True)


type Msg
  = Locked Bool
  | Hidden Bool
  | Private Bool
  | Nolastmod Bool
  | Delete Bool
  | Content TP.Msg
  | Title String
  | BoardDel Int
  | BoardSearch (A.Msg GApi.ApiBoardResult)
  | PollEnabled Bool
  | PollQ String
  | PollMax (Maybe Int)
  | PollOpt Int String
  | PollRem Int
  | PollAdd
  | Submit
  | Submitted GApi.Response


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    Locked  b     -> ({ model | locked  = b }, Cmd.none)
    Hidden  b     -> ({ model | hidden  = b }, Cmd.none)
    Private b     -> ({ model | private = b }, Cmd.none)
    Nolastmod b   -> ({ model | nolastmod=b }, Cmd.none)
    Delete  b     -> ({ model | delete  = b }, Cmd.none)
    Content m     -> let (nm,nc) = TP.update m model.msg in ({ model | msg = nm }, Cmd.map Content nc)
    Title   s     -> ({ model | title   = Just s }, Cmd.none)
    PollEnabled b -> ({ model | pollEnabled = b, poll = if model.poll == Nothing then Just { question = "", max_options = 1, options = ["",""] } else model.poll }, Cmd.none)
    PollQ s       -> ({ model | poll = Maybe.map (\p -> { p | question    = s}) model.poll }, Cmd.none)
    PollMax n     -> ({ model | poll = Maybe.map (\p -> { p | max_options = Maybe.withDefault 0 n}) model.poll }, Cmd.none)
    PollOpt n s   -> ({ model | poll = Maybe.map (\p -> { p | options = modidx n (always s) p.options }) model.poll }, Cmd.none)
    PollRem n     -> ({ model | poll = Maybe.map (\p -> { p | options = delidx n p.options }) model.poll }, Cmd.none)
    PollAdd       -> ({ model | poll = Maybe.map (\p -> { p | options = p.options ++ [""] }) model.poll }, Cmd.none)

    BoardDel i    -> ({ model | boards  = Maybe.map (\b -> delidx i b) model.boards }, Cmd.none)
    BoardSearch m ->
      let (nm, c, res) = A.update searchConfig m model.boardAdd
      in case res of
        Nothing -> ({ model | boardAdd = nm }, c)
        Just r  -> ({ model | boardAdd = A.clear nm "", boards = Maybe.map (\b -> b ++ [r]) model.boards }, c)

    Submit -> ({ model | state = Api.Loading }, GDE.send (encode model) Submitted)
    Submitted (GApi.Redirect s) -> (model, load s)
    Submitted r -> ({ model | state = Api.Error r }, Cmd.none)


view : Model -> Html Msg
view model =
  let
    board n bd =
      li [] <|
        [ text "["
        , a [ href "#", onClickD (BoardDel n), tabindex 10 ] [ text "remove" ]
        , text "] "
        , text (Maybe.withDefault "" (lookup bd.btype boardTypes))
        ] ++ case (bd.btype, bd.iid, bd.title) of
          (_, Just iid, Just title) ->
            [ b [ class "grayedout" ] [ text " > " ]
            , a [ href <| "/" ++ iid ] [ text title ]
            ]
          ("u", Just iid, _) -> [ b [ class "grayedout" ] [ text " > " ], text <| iid ++ " (deleted)" ]
          _ -> []

    boards () =
      [ text "You can link this thread to multiple boards. Every visual novel, producer and user in the database has its own board,"
      , text " but you can also use the \"General Discussions\" and \"VNDB Discussions\" boards for threads that do not fit at a particular database entry."
      , ul [ style "list-style-type" "none", style "margin" "10px" ] <| List.indexedMap board (Maybe.withDefault [] model.boards)
      , A.view searchConfig model.boardAdd [placeholder "Add boards..."]
      ] ++
        if model.boards == Just []
        then [ b [ class "standout" ] [ text "Please add at least one board." ] ]
        else if dupBoards model
        then [ b [ class "standout" ] [ text "List contains duplicates." ] ]
        else []

    pollOpt n p =
      li []
      [ inputText "" p (PollOpt n) (style "width" "400px" :: placeholder ("Option #" ++ String.fromInt (n+1)) :: GDE.valPollOptions)
      , if numPollOptions model > 2
        then a [ href "#", onClickD (PollRem n), tabindex 10 ] [ text "remove" ]
        else text ""
      ]

    poll =
      [ tr [ class "newpart" ] [ td [ colspan 2 ] [ text "" ] ]
      , formField "" [ label [] [ inputCheck "" model.pollEnabled PollEnabled, text " Add poll" ] ]
      ] ++
      case (model.pollEnabled, model.poll) of
        (True, Just p) ->
          [ if model.pollEdit
            then formField "" [ b [ class "standout" ] [ text "Votes will be reset if any changes are made to these options!" ] ]
            else text ""
          , formField "pollq::Poll question" [ inputText "pollq" p.question PollQ (style "width" "400px" :: GDE.valPollQuestion) ]
          , formField "Options"
            [ ul [ style "list-style-type" "none", style "margin" "0px" ] <| List.indexedMap pollOpt p.options
            , if numPollOptions model < 20
              then a [ href "#", onClickD PollAdd, tabindex 10 ] [ text "Add option" ]
              else text ""
            ]
          , formField ""
            [ inputNumber "" (Just p.max_options) PollMax <| GDE.valPollMax_Options ++ [ Html.Attributes.max <| String.fromInt <| List.length p.options ]
            , text "  Number of options people are allowed to choose."
            ]
          ]
        (_, _) -> []


  in
  form_ "" Submit (model.state == Api.Loading)
  [ div [ class "mainbox" ]
    [ h1 [] [ text <| if model.tid == Nothing then "Create new thread" else "Edit thread" ]
    , table [ class "formtable" ] <|
      [ formField "title::Thread title" [ inputText "title" (Maybe.withDefault "" model.title) Title (style "width" "400px" :: required True :: GDE.valTitle) ]
      , if model.can_mod
        then formField "" [ label [] [ inputCheck "" model.locked Locked, text " Locked" ] ]
        else text ""
      , if model.can_mod
        then formField "" [ label [] [ inputCheck "" model.hidden Hidden, text " Hidden" ] ]
        else text ""
      , if model.can_private
        then formField "" [ label [] [ inputCheck "" model.private Private, text " Private" ] ]
        else text ""
      , if model.tid /= Nothing && model.can_mod
        then formField "" [ label [] [ inputCheck "" model.nolastmod Nolastmod, text " Don't update last modification timestamp" ] ]
        else text ""
      , formField "boardadd::Boards" (boards ())
      , tr [ class "newpart" ] [ td [ colspan 2 ] [ text "" ] ]
      , formField "msg::Message"
        [ TP.view "msg" model.msg Content 700 ([rows 12, cols 50] ++ GDE.valMsg)
          [ b [ class "standout" ] [ text " (English please!) " ]
          , a [ href "/d9#3" ] [ text "Formatting" ]
          ]
        ]
      ]
      ++ poll
      ++ (if not model.can_mod || model.tid == Nothing then [] else
      [ tr [ class "newpart" ] [ td [ colspan 2 ] [ text "DANGER ZONE" ] ]
      , formField "" [ inputCheck "" model.delete Delete, text " Permanently delete this thread and all replies. This action can not be reverted, only do this with obvious spam!" ]
      ])
    ]
  , div [ class "mainbox" ]
    [ fieldset [ class "submit" ] [ submitButton "Submit" model.state (isValid model) ] ]
  ]
