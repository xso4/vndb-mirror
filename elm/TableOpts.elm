module TableOpts exposing (main)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Browser
import Bitwise as B
import Lib.DropDown as DD
import Lib.Api as Api
import Lib.Html exposing (..)
import Gen.Api as GApi
import Gen.TableOptsSave as GTO


main : Program GTO.Recv Model Msg
main = Browser.element
  { init   = \e -> (init e, Cmd.none)
  , view   = view
  , update = update
  , subscriptions = \model -> DD.sub model.dd
  }

type alias Model =
  { opts    : GTO.Recv
  , state   : Api.State
  , saved   : Bool
  , dd      : DD.Config Msg
  , view    : Int
  , results : Int
  , asc     : Bool
  , sort    : Int
  , cols    : Int
  }

init : GTO.Recv -> Model
init opts =
  { opts    = opts
  , state   = Api.Normal
  , saved   = False
  , dd      = DD.init "tableopts" Open
  , view    = B.and 3 opts.value
  , results = B.and 7 (B.shiftRightBy 2 opts.value)
  , asc     = B.and 32 opts.value == 0
  , sort    = B.and 63 (B.shiftRightBy 6 opts.value)
  , cols    = B.shiftRightBy 12 opts.value
  }


type Msg
  = Open Bool
  | View Int Bool
  | Results Int Bool
  | Save
  | Saved GApi.Response


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    Open b      -> ({ model | saved = False, dd = DD.toggle model.dd b }, Cmd.none)
    View n _    -> ({ model | saved = False, view = n }, Cmd.none)
    Results n _ -> ({ model | saved = False, results = n }, Cmd.none)
    Save        -> ( { model | saved = False, state = Api.Loading }
                   , GTO.send { save = Maybe.withDefault "" model.opts.save
                              , value = if encInt model == model.opts.default then Nothing else Just (encInt model)
                              } Saved)
    Saved GApi.Success -> ({ model | saved = True, state = Api.Normal }, Cmd.none)
    Saved e -> ({ model | state = Api.Error e }, Cmd.none)


encBase64Alpha : Int -> String
encBase64Alpha n = String.slice n (n+1) "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_-"

encBase64 : Int -> String
encBase64 n = (if n >= 64 then encBase64 (n//64) else "") ++ encBase64Alpha (modBy 64 n)

encInt : Model -> Int
encInt m =
     B.xor m.view
  <| B.xor (B.shiftLeftBy 2 m.results)
  <| B.xor (if m.asc then 0 else 32)
  <| B.xor (B.shiftLeftBy 6 m.sort)
  <| B.shiftLeftBy 12 m.cols

view : Model -> Html Msg
view model = div []
  [ if model.opts.save == Nothing && encInt model == model.opts.default
    then text ""
    else input [ type_ "hidden", name "s", value (encBase64 (encInt model)) ] []
  , DD.view model.dd Api.Normal
      (text "display options")
      (\_ -> [ table [ style "min-width" "300px" ]
        [ tr [] [ td [] [ text "Format" ], td [] -- TODO: Icons, or some sort of preview?
          [ linkRadio (model.view == 0) (View 0) [ text "Rows"  ], text " / "
          , linkRadio (model.view == 1) (View 1) [ text "Cards" ], text " / "
          , linkRadio (model.view == 2) (View 2) [ text "Grid"  ]
          ] ]
        , tr [] [ td [] [ text "Results" ], td []
          [ linkRadio (model.results == 1) (Results 1) [ text "10"  ], text " / "
          , linkRadio (model.results == 2) (Results 2) [ text "25"  ], text " / "
          , linkRadio (model.results == 0) (Results 0) [ text "50"  ], text " / "
          , linkRadio (model.results == 3) (Results 3) [ text "100" ], text " / "
          , linkRadio (model.results == 4) (Results 4) [ text "200" ]
          ] ]
        , tr [] [ td [] [], td []
          [ input [ type_ "submit", class "submit", value "Update" ] []
          , case (model.opts.save, model.saved) of
              (_, True) -> text "Saved!"
              (Just _, _) -> inputButton "Save as default" Save []
              _ -> text ""
          , case model.state of
              Api.Normal  -> text ""
              Api.Loading -> span [ class "spinner" ] []
              Api.Error e -> b [ class "standout" ] [ text <| Api.showResponse e ]
          ] ]
        ]
      ])
  ]
