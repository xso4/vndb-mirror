module UList.SaveDefault exposing (main)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Browser
import Lib.Html exposing (..)
import Lib.Util exposing (..)
import Lib.Api as Api
import Gen.Api as GApi
import Gen.UListSaveDefault as GUSD


main : Program GUSD.Recv Model Msg
main = Browser.element
  { init   = \e -> (init e, Cmd.none)
  , view   = view
  , update = update
  , subscriptions = always Sub.none
  }

type alias Model =
  { state : Api.State
  , uid   : Int
  , opts  : GUSD.SendOpts
  , field : String -- Ewwww stringly typed enum
  , hid   : Bool
  }

init : GUSD.Recv -> Model
init d =
  { state = Api.Normal
  , uid   = d.uid
  , opts  = d.opts
  , field = "vnlist"
  , hid   = True
  }

type Msg
  = SetField String
  | Submit
  | Submitted GApi.Response


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    SetField s -> ({ model | field = s, hid = False }, Cmd.none)

    Submit ->
      ( { model | state = Api.Loading, hid = False }
      , GUSD.send { uid = model.uid, opts = model.opts, field = model.field } Submitted)
    Submitted GApi.Success -> ({ model | state = Api.Normal, hid = True }, Cmd.none)
    Submitted r -> ({ model | state = Api.Error r }, Cmd.none)


view : Model -> Html Msg
view model =
  form_ "" Submit (model.state == Api.Loading)
  [ div [ classList [("savedefault", True), ("hidden", model.hid)] ]
    [ b [] [ text "Save as default" ]
    , br [] []
    , text "This will change the default label selection, visible columns and table sorting options for the selected page to the currently applied settings."
    , text " The saved view will also apply to users visiting your lists."
    , br [] []
    , text "(If you just changed the label filters, make sure to hit \"Update filters\" before saving)"
    , br [] []
    , label [] [ inputRadio "savedefault_page" (model.field == "votes")  (always (SetField "votes") ), text " My Votes" ]
    , br [] []
    , label [] [ inputRadio "savedefault_page" (model.field == "vnlist") (always (SetField "vnlist")), text " My Visual Novel List" ]
    , br [] []
    , label [] [ inputRadio "savedefault_page" (model.field == "wish")   (always (SetField "wish")  ), text " My Wishlist" ]
    , br [] []
    , submitButton "Save" model.state True
    ]
  ]
