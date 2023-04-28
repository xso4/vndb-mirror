module User.Register exposing (main)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Browser
import Lib.Api as Api
import Gen.Api as GApi
import Gen.UserRegister as GUR
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
  { username : String
  , email    : String
  , vns      : Int
  , c18      : Bool
  , cpolicy  : Bool
  , state    : Api.State
  , success  : Bool
  }


init : Model
init =
  { username = ""
  , email    = ""
  , vns      = 0
  , c18      = False
  , cpolicy  = False
  , state    = Api.Normal
  , success  = False
  }


type Msg
  = Username String
  | EMail String
  | VNs String
  | C18 Bool
  | CPolicy Bool
  | Submit
  | Submitted GApi.Response


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    Username n -> ({ model | username = n }, Cmd.none)
    EMail    n -> ({ model | email    = n }, Cmd.none)
    C18      b -> ({ model | c18      = b }, Cmd.none)
    CPolicy  b -> ({ model | cpolicy  = b }, Cmd.none)
    VNs      n -> ({ model | vns      = Maybe.withDefault model.vns (String.toInt n) }, Cmd.none)

    Submit -> ( { model | state = Api.Loading }
              , GUR.send { username = model.username, email = model.email, vns = model.vns } Submitted )

    Submitted GApi.Success      -> ({ model | success = True }, Cmd.none)
    Submitted e                 -> ({ model | state = Api.Error e }, Cmd.none)


view : Model -> Html Msg
view model =
  if model.success
  then
    article []
    [ h1 [] [ text "Account created" ]
    , div [ class "notice" ]
      [ p []
        [ text "Your account has been created! In a few minutes, you should receive an email with instructions to set your password."
        , br_ 1
        , text "(make sure to check your spam box if it doesn't seem to be arriving)"
        ] ]
    ]
  else
    form_ "" Submit (model.state == Api.Loading)
    [ article []
      [ h1 [] [ text "Create an account" ]
      , table [ class "formtable" ]
        [ formField "username::Username"
          [ inputText "username" model.username Username GUR.valUsername
          , br_ 1
          , text "Preferred username. Must be between 2 and 15 characters long and consist entirely of alphanumeric characters or a dash."
          , text " Names that look like database identifiers (i.e. a single letter followed by several numbers) are also disallowed."
          ]
        , formField "email::E-Mail"
          [ inputText "email" model.email EMail GUR.valEmail
          , br_ 1
          , text "A valid address is required in order to activate and use your account. "
          , text "Other than that, your address is only used in case you lose your password, "
          , text "we will never send spam or newsletters unless you explicitly ask us for it or we get hacked."
          , br_ 3
          , text "Anti-bot question: How many visual novels do we have in the database? (Hint: look to your left)"
          ]
        , formField "vns::Answer" [ inputText "vns" (if model.vns == 0 then "" else String.fromInt model.vns) VNs [] ]
        , formField ""
          [ br [] []
          , label [] [ inputCheck "" model.c18 C18, text " I am 18 years or older." ]
          , br [] []
          , label [] [ inputCheck "" model.cpolicy CPolicy, text " I have read the ", a [ href "/d17" ] [ text "privacy policy and contributor license agreement" ], text "." ]
          ]
        ]
      ]
    , article []
      [ fieldset [ class "submit" ] <|
        if model.c18 && model.cpolicy then [ submitButton "Submit" model.state True ] else []
      ]
    ]
