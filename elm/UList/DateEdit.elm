module UList.DateEdit exposing (main,init,view,update,Model,Msg)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Task
import Process
import Browser
import Regex
import Lib.Html exposing (..)
import Lib.Api as Api
import Gen.Api as GApi
import Gen.UListDateEdit as GDE


main : Program GDE.Send Model Msg
main = Browser.element
  { init = \f -> (init f, Cmd.none)
  , subscriptions = always Sub.none
  , view = view
  , update = update
  }

type alias Model =
  { state   : Api.State
  , flags   : GDE.Send
  , val     : String
  , valid   : Bool
  , debnum  : Int -- Debounce for submit
  , visible : Bool
  }

init : GDE.Send -> Model
init f =
  { state   = Api.Normal
  , flags   = f
  , val     = f.date
  , valid   = True
  , debnum  = 0
  , visible = False
  }

type Msg
  = Show
  | Val String Bool
  | Save Int
  | Saved GApi.Response

isDate : String -> Bool
isDate s
  = Regex.fromString "^(?:19[7-9][0-9]|20[0-9][0-9])-(?:0[1-9]|1[0-2])-(?:0[1-9]|[12][0-9]|3[01])$"
  |> Maybe.map (\r -> Regex.contains r s) |> Maybe.withDefault True

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    Show    -> ({ model | visible = True }, Cmd.none)
    Val s b ->
      ({ model | val = s, debnum = model.debnum + 1, valid = b && (s == "" || isDate s) }
      , Task.perform (\_ -> Save (model.debnum+1)) <| Process.sleep 300)

    Save n ->
      if n /= model.debnum || model.val == model.flags.date || not model.valid
      then (model, Cmd.none)
      else ( { model | state = Api.Loading, debnum = model.debnum+1 }
           , GDE.send { vid = model.flags.vid, start = model.flags.start, date = model.val } Saved )

    Saved GApi.Success ->
      let f  = model.flags
          nf = { f | date = model.val }
      in ({ model | state = Api.Normal, flags = nf }, Cmd.none)
    Saved e -> ({ model | state = Api.Error e }, Cmd.none)


view : Model -> Html Msg
view model = div (class "compact" :: if model.visible then [] else [onMouseOver Show]) <|
  case model.state of
    Api.Loading -> [ span [ class "spinner" ] [] ]
    Api.Error _ -> [ b [] [ text "error" ] ] -- Argh
    Api.Normal ->
      [ if model.visible
        then input [ type_ "date", class "text", value model.val, onInputValidation Val, onBlur (Save model.debnum), placeholder "yyyy-mm-dd" ] []
        else text ""
      , span [] [ text model.val ]
      ]
