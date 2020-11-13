module User.PassSet exposing (main)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Browser
import Browser.Navigation exposing (load)
import Lib.Api as Api
import Gen.Api as GApi
import Gen.UserPassSet as GUPS
import Lib.Html exposing (..)


main : Program GUPS.Recv Model Msg
main = Browser.element
  { init = \f -> (init f, Cmd.none)
  , subscriptions = always Sub.none
  , view = view
  , update = update
  }


type alias Model =
  { token    : String
  , uid      : Int
  , newpass1 : String
  , newpass2 : String
  , state    : Api.State
  , noteq    : Bool
  }


init : GUPS.Recv -> Model
init f =
  { token    = f.token
  , uid      = f.uid
  , newpass1 = ""
  , newpass2 = ""
  , state    = Api.Normal
  , noteq    = False
  }


type Msg
  = Newpass1 String
  | Newpass2 String
  | Submit
  | Submitted GApi.Response


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    Newpass1 n -> ({ model | newpass1 = n, noteq = False }, Cmd.none)
    Newpass2 n -> ({ model | newpass2 = n, noteq = False }, Cmd.none)

    Submit ->
      if model.newpass1 /= model.newpass2
      then ( { model | noteq = True }, Cmd.none)
      else ( { model | state = Api.Loading }
           , GUPS.send { token = model.token, uid = model.uid, password = model.newpass1 } Submitted )

    Submitted GApi.Success -> (model, load "/")
    Submitted e            -> ({ model | state = Api.Error e }, Cmd.none)


view : Model -> Html Msg
view model =
  form_ "" Submit (model.state == Api.Loading)
  [ div [ class "mainbox" ]
    [ h1 [] [ text "Set your password" ]
    , p [] [ text "Now you can set a password for your account. You will be logged in automatically after your password has been saved." ]
    , table [ class "formtable" ]
      [ formField "newpass1::New password" [ inputPassword "newpass1" model.newpass1 Newpass1 GUPS.valPassword ]
      , formField "newpass2::Repeat"
        [ inputPassword "newpass2" model.newpass2 Newpass2 GUPS.valPassword
        , br_ 1
        , if model.noteq then b [ class "standout" ] [ text "Passwords do not match" ] else text ""
        ]
      ]
   ]
  , div [ class "mainbox" ]
    [ fieldset [ class "submit" ] [ submitButton "Submit" model.state True ]
    ]
  ]
