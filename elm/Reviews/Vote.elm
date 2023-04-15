module Reviews.Vote exposing (main)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Browser
import Lib.Util exposing (..)
import Lib.Html exposing (..)
import Lib.Api as Api
import Gen.Api as GApi
import Gen.ReviewsVote as GRV


main : Program GRV.Recv Model Msg
main = Browser.element
  { init = \d -> (init d, Cmd.none)
  , subscriptions = always Sub.none
  , view = view
  , update = update
  }

type alias Model =
  { state    : Api.State
  , id       : String
  , my       : Maybe Bool
  , overrule : Bool
  , mod      : Bool
  }

init : GRV.Recv -> Model
init d =
  { state    = Api.Normal
  , id       = d.id
  , my       = d.my
  , overrule = d.overrule
  , mod      = d.mod
  }

type Msg
  = Vote Bool
  | Overrule Bool
  | Saved GApi.Response


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  let save m = ({ m | state = Api.Loading }, GRV.send { id = m.id, my = m.my, overrule = m.overrule } Saved)
  in
  case msg of
    Vote b     -> save { model | my = if model.my == Just b then Nothing else Just b }
    Overrule b -> let nm = { model | overrule = b } in if isJust model.my then save nm else (nm, Cmd.none)

    Saved GApi.Success -> ({ model | state = Api.Normal }, Cmd.none)
    Saved e -> ({ model | state = Api.Error e }, Cmd.none)


view : Model -> Html Msg
view model =
  let but opt lbl = a [ href "#", onClickD (Vote opt), classList [("votebut", True), ("myvote", model.my == Just opt)] ] [ text lbl ]
  in
  span []
  [ case model.state of
      Api.Loading -> span [ class "spinner" ] []
      Api.Error e -> b [] [ text (Api.showResponse e) ]
      Api.Normal  -> text "Was this review helpful? "
  , but True "yes"
  , text " / "
  , but False "no"
  , if not model.mod then text "" else label [] [ text " / ", inputCheck "" model.overrule Overrule, text " O" ]
  ]
