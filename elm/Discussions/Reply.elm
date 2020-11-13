module Discussions.Reply exposing (main)

import Html exposing (..)
import Html.Attributes exposing (..)
import Browser
import Browser.Navigation exposing (load,reload)
import Lib.Html exposing (..)
import Lib.TextPreview as TP
import Lib.Api as Api
import Gen.Api as GApi
import Gen.DiscussionsReply as GDR


main : Program GDR.Recv Model Msg
main = Browser.element
  { init   = \e -> (init e, Cmd.none)
  , view   = view
  , update = update
  , subscriptions = always Sub.none
  }


type alias Model =
  { state  : Api.State
  , tid    : String
  , old    : Bool
  , msg    : TP.Model
  }


init : GDR.Recv -> Model
init e =
  { state  = Api.Normal
  , tid    = e.tid
  , old    = e.old
  , msg    = TP.bbcode ""
  }


type Msg
  = NotOldAnymore
  | Content TP.Msg
  | Submit
  | Submitted GApi.Response


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    NotOldAnymore -> ({ model | old = False }, Cmd.none)
    Content m -> let (nm,nc) = TP.update m model.msg in ({ model | msg = nm }, Cmd.map Content nc)

    Submit -> ({ model | state = Api.Loading }, GDR.send { msg = model.msg.data, tid = model.tid } Submitted)
    -- Reload is necessary because s may be the same as the current URL (with a location.hash)
    Submitted (GApi.Redirect s) -> (model, Cmd.batch [ load s, reload ])
    Submitted r -> ({ model | state = Api.Error r }, Cmd.none)


view : Model -> Html Msg
view model =
  form_ "" Submit (model.state == Api.Loading)
  [ div [ class "mainbox" ] <| [
    if model.old
    then
      p [ class "center" ]
      [ text "This thread has not seen any activity for more than 6 months, but you may still "
      , a [ href "#", onClickD NotOldAnymore ] [ text "reply" ]
      , text " if you have something relevant to add."
      , text " If your message is not directly relevant to this thread, perhaps it's better to "
      , a [ href "/t/ge/new" ] [ text "create a new thread" ]
      , text " instead."
      ]
    else
      fieldset [ class "submit" ]
      [ TP.view "msg" model.msg Content 600 ([rows 4, cols 50] ++ GDR.valMsg)
        [ b [] [ text "Quick reply" ]
        , b [ class "standout" ] [ text " (English please!) " ]
        , a [ href "/d9#3" ] [ text "Formatting" ]
        ]
      , submitButton "Submit" model.state True
      ]
  ] ]
