module User.Login exposing (main)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Browser
import Browser.Navigation exposing (load)
import Lib.Api as Api
import Gen.Api as GApi
import Gen.UserLogin as GUL
import Gen.UserChangePass as GUCP
import Gen.Types exposing (adminEMail)
import Lib.Html exposing (..)


main : Program String Model Msg
main = Browser.element
  { init = \ref -> (init ref, Cmd.none)
  , subscriptions = always Sub.none
  , view = view
  , update = update
  }


type alias Model =
  { ref      : String
  , username : String
  , password : String
  , newpass1 : String
  , newpass2 : String
  , state    : Api.State
  , insecure : Bool
  , noteq    : Bool
    -- Extra Elm-side input validation, because apparently some login managers
    -- bypass HTML5 validation or proper onChange messages fail to get invoked.
  , invalid  : Bool
  }


init : String -> Model
init ref =
  { ref      = ref
  , username = ""
  , password = ""
  , newpass1 = ""
  , newpass2 = ""
  , state    = Api.Normal
  , insecure = False
  , noteq    = False
  , invalid  = False
  }


type Msg
  = Username String
  | Password String
  | Newpass1 String
  | Newpass2 String
  | Submit
  | Submitted GApi.Response


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    Username n -> ({ model | invalid = False, username = String.toLower n }, Cmd.none)
    Password n -> ({ model | invalid = False, password = n }, Cmd.none)
    Newpass1 n -> ({ model | newpass1 = n, noteq = False }, Cmd.none)
    Newpass2 n -> ({ model | newpass2 = n, noteq = False }, Cmd.none)

    Submit ->
      if model.username == "" || model.password == ""
      then ( { model | invalid = True }, Cmd.none)
      else if not model.insecure
      then ( { model | state = Api.Loading }
           , GUL.send { username = model.username, password = model.password } Submitted )
      else if model.newpass1 /= model.newpass2
      then ( { model | noteq = True }, Cmd.none )
      else ( { model | state = Api.Loading }
           , GUCP.send { username = model.username, oldpass = model.password, newpass = model.newpass1 } Submitted )

    Submitted GApi.Success      -> (model, load model.ref)
    Submitted GApi.InsecurePass -> ({ model | insecure = True, state = if model.insecure then Api.Error GApi.InsecurePass else Api.Normal }, Cmd.none)
    Submitted e                 -> ({ model | state = Api.Error e }, Cmd.none)


view : Model -> Html Msg
view model =
  let
    loginBox =
      div [ class "mainbox" ]
      [ h1 [] [ text "Login" ]
      , table [ class "formtable" ]
        [ formField "username::Username"
          [ inputText "username" model.username Username GUL.valUsername
          , br_ 1
          , a [ href "/u/register" ] [ text "No account yet?" ]
          ]
        , formField "password::Password"
          [ inputPassword "password" model.password Password GUL.valPassword
          , br_ 1
          , a [ href "/u/newpass" ] [ text "Forgot your password?" ]
          ]
        ]
     , if model.state == Api.Normal || model.state == Api.Loading
       then text ""
       else div [ class "notice" ]
            [ h2 [] [ text "Trouble logging in?" ]
            , text "If you have not used this login form since October 2014, your account has likely been disabled. You can "
            , a [ href "/u/newpass" ] [ text "reset your password" ]
            , text " to regain access."
            , br_ 2
            , text "Still having trouble? Send a mail to "
            , a [ href <| "mailto:" ++ adminEMail ] [ text adminEMail ]
            , text ". But keep in mind that I can only help you if the email address associated with your account is correct"
            , text " and you still have access to it. Without that, there is no way to prove that the account is yours."
            ]
      ]

    changeBox =
      div [ class "mainbox" ]
      [ h1 [] [ text "Change your password" ]
      , div [ class "warning" ]
        [ h2 [] [ text "Your current password is not secure" ]
        , text "Your current password is in a public database of leaked passwords. You need to change it before you can continue."
        ]
      , table [ class "formtable" ]
        [ formField "newpass1::New password" [ inputPassword "newpass1" model.newpass1 Newpass1 GUCP.valNewpass ]
        , formField "newpass2::Repeat"
          [ inputPassword "newpass2" model.newpass2 Newpass2 GUCP.valNewpass
          , br_ 1
          , if model.noteq then b [ class "standout" ] [ text "Passwords do not match" ] else text ""
          ]
        ]
      ]

  in form_ "" Submit (model.state == Api.Loading)
      [ if model.insecure then changeBox else loginBox
      , div [ class "mainbox" ]
        [ fieldset [ class "submit" ]
          [ if model.invalid then b [ class "standout" ] [ text "Username or password is empty." ] else text ""
          , submitButton "Submit" model.state (not model.invalid)
          ]
        ]
      ]
