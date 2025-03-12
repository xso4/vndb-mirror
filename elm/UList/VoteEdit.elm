port module UList.VoteEdit exposing (main, init, update, view, Model, Msg)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Browser
import Task
import Lib.Html exposing (..)
import Lib.Util exposing (..)
import Lib.Api as Api
import Lib.Ffi as Ffi
import Lib.DropDown as DD
import Gen.Types exposing (ratings)
import Gen.Api as GApi
import Gen.UListVoteEdit as GVE


main : Program GVE.Send Model Msg
main = Browser.element
  { init = \f -> (init f, Cmd.none)
  , subscriptions = \model -> DD.sub model.dd
  , view = \m -> view m "-"
  , update = update
  }

port ulistVoteChanged : Bool -> Cmd msg

type alias Model =
  { state   : Api.State
  , flags   : GVE.Send
  , dd      : DD.Config Msg
  , text    : String
  , vote    : Maybe String
  , ovote   : Maybe String
  , isvalid : Bool
  , fieldId : String
  }

init : GVE.Send -> Model
init f =
  let v = if f.vote == Just "-" || f.vote == Just "" then Nothing else f.vote
  in
  { state   = Api.Normal
  , flags   = f
  , dd      = DD.init ("vote_edit_dd_" ++ f.vid) Open
  , text    = if List.any (\n -> v == Just (String.fromInt n)) (List.indexedMap (\a b -> a+1) ratings) then "" else Maybe.withDefault "" v
  , vote    = v
  , ovote   = v
  , isvalid = True
  , fieldId = "vote_edit_" ++ f.vid
  }

type Msg
  = Input String Bool
  | Open Bool
  | Set (Maybe String) Bool
  | Noop
  | Focus
  | Save
  | Saved GApi.Response


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    Input s b -> let t = String.replace "," "." s in ({ model | text = t, isvalid = b, vote = if not b then model.vote else if t == "" || t == "-" then Nothing else Just t }, Cmd.none)
    Open b  -> ({ model | dd = DD.toggle model.dd b }, if b then selfCmd Focus else Cmd.none)
    Set s b -> ({ model | text = "", vote = s, isvalid = True, dd = DD.toggle model.dd False }, selfCmd Save)
    Noop  -> (model, Cmd.none)
    Focus -> (model, Task.attempt (always Noop) <| Ffi.elemCall "select" model.fieldId)

    Save ->
      case (model.vote == model.ovote, model.isvalid) of
        (True, _)  -> (model, Cmd.none)
        (_, False) -> (model, Task.attempt (always Noop) <| Ffi.elemCall "reportValidity" model.fieldId)
        (_, _)     -> ( { model | state = Api.Loading, ovote = model.vote, dd = DD.toggle model.dd False }
                      , GVE.send { vid = model.flags.vid, vote = model.vote } Saved)

    Saved GApi.Success -> ({ model | state = Api.Normal }, ulistVoteChanged (isJust (model.vote)))
    Saved e -> ({ model | state = Api.Error e }, Cmd.none)


view : Model -> String -> Html Msg
view model txt =
  div [ class "elm_votedd" ]
  [ DD.view model.dd model.state
      (text <| Maybe.withDefault txt model.ovote)
      <| \_ ->
      [ ul [] <|
        List.indexedMap (\n s ->
          let sn = String.fromInt (10-n)
          in li [] [ linkRadio (Just sn == model.ovote) (Set (Just sn)) [ text <| sn ++ " (" ++ s ++ ")" ] ]
        ) (List.reverse ratings)
        ++
        [ li [] [ Html.form [ onSubmit Save ] [ p []
          [ text "custom: "
          , input (
              [ type_ "text"
              , class "text"
              , id model.fieldId
              , value model.text
              , onInputValidation Input
              , onBlur Save
              , onFocus Focus
              , placeholder "7.5"
              , style "width" "55px"
              , pattern "(?:^(?:|-|[1-9]|10|[1-9]\\.[0-9]|10\\.0)$)"
              ]
            ) []
          ] ]
        ] ]
        ++
        ( if isJust (model.ovote)
          then [ li [] [ a [ href "#", onClickD (Set Nothing True) ] [ text "remove vote" ] ] ]
          else []
        )
      ]
  ]
