module UList.ReleaseEdit exposing (main, init, update, view, Model, Msg(..))

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Browser
import Lib.Util exposing (..)
import Lib.Html exposing (..)
import Lib.Api as Api
import Lib.DropDown as DD
import Gen.Types exposing (rlistStatus)
import Gen.Api as GApi
import Gen.UListRStatus as GRS


main : Program GRS.Send Model Msg
main = Browser.element
  { init = \f -> (init "" f, Cmd.none)
  , subscriptions = \model -> DD.sub model.dd
  , view = view
  , update = update
  }

type alias Model =
  { uid      : String
  , rid      : String
  , status   : Maybe Int
  , empty    : String
  , state    : Api.State
  , dd       : DD.Config Msg
  }

init : String -> GRS.Send -> Model
init vid f =
  { uid      = f.uid
  , rid      = f.rid
  , status   = f.status
  , empty    = f.empty
  , state    = Api.Normal
  , dd       = DD.init ("ulist_reldd" ++ vid ++ "_" ++ f.rid) Open
  }

type Msg
  = Open Bool
  | Set (Maybe Int) Bool
  | Saved GApi.Response


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    Open b -> ({ model | dd = DD.toggle model.dd b }, Cmd.none)
    Set st _ ->
      ( { model | dd = DD.toggle model.dd False, status = st, state = Api.Loading }
      , GRS.send { uid = model.uid, rid = model.rid, status = st, empty = "" } Saved )

    Saved GApi.Success -> ({ model | state = Api.Normal }, Cmd.none)
    Saved e -> ({ model | state = Api.Error e }, Cmd.none)


view : Model -> Html Msg
view model =
  DD.view model.dd model.state
    (text <| Maybe.withDefault model.empty <| Maybe.andThen (\s -> lookup s rlistStatus) model.status)
    <| \_ ->
      [ ul [] <| List.map (\(n, status) ->
          li [ ] [ linkRadio (Just n == model.status) (Set (Just n)) [ text status ] ]
        ) rlistStatus
        ++ [ li [] [ a [ href "#", onClickD (Set Nothing True) ] [ text "remove" ] ] ]
      ]
