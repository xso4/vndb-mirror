module User.PassReset exposing (main)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Browser
import Lib.Api as Api
import Gen.Api as GApi
import Gen.UserPassReset as GUPR
import Lib.Html exposing (..)
import Lib.Util exposing (..)


main : Program () Model Msg
main = Browser.element
  { init = always (init, Cmd.none)
  , subscriptions = always Sub.none
  , view = view
  , update = update
  }


type alias Model =
  { email    : String
  , state    : Api.State
  , success  : Bool
  }


init : Model
init =
  { email    = ""
  , state    = Api.Normal
  , success  = False
  }


type Msg
  = EMail String
  | Submit
  | Submitted GApi.Response


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    EMail n -> ({ model | email    = n }, Cmd.none)
    Submit -> ({ model | state = Api.Loading }, GUPR.send { email = model.email } Submitted)
    Submitted GApi.Success -> ({ model | success = True }, Cmd.none)
    Submitted e            -> ({ model | state = Api.Error e }, Cmd.none)


view : Model -> Html Msg
view model =
  if model.success
  then
    article []
    [ h1 [] [ text "New password" ]
    , div [ class "notice" ]
      [ p []
        [ text "Instructions to set a new password should reach your mailbox in a few minutes."
        , br_ 1
        , text "(make sure to check your spam box if the mail doesn't seem to be arriving)"
        ] ]
    ]
  else
    form_ "" Submit (model.state == Api.Loading)
    [ article []
      [ h1 [] [ text "Forgot Password" ]
      , p []
        [ text "Forgot your password and can't login to VNDB anymore? "
        , text "Don't worry! Just give us the email address you used to register on VNDB "
        , text " and we'll send you instructions to set a new password within a few minutes!"
        ]
      , table [ class "formtable" ]
        [ formField "email::E-Mail" [ inputText "email" model.email EMail GUPR.valEmail ] ]
      ]
    , article [ class "submit" ] [ submitButton "Submit" model.state True ]
    ]
