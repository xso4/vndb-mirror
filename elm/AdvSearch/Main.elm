module AdvSearch.Main exposing (main)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Browser
import Json.Encode as JE
import Json.Decode as JD
import AdvSearch.Query exposing (..)
import AdvSearch.Fields exposing (..)


main : Program JE.Value Model Msg
main = Browser.element
  { init   = \e -> (init e, Cmd.none)
  , view   = view
  , update = update
  , subscriptions = \m -> fquerySub [] Field m.query
  }


type alias Model =
  { query : FQuery
  }


init : JE.Value -> Model
init arg =
  -- TODO: Sort and add (empty) fields for quick select mode, it's kind of useless like this
  { query = JD.decodeValue decodeQuery arg |> Result.toMaybe |> Maybe.map (Tuple.second << fqueryFromQuery 1) |> Maybe.withDefault (FAnd [])
  }

type Msg
  = Field (List Int) FieldMsg


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    Field path m ->
      case fqueryGet path model.query of
        Just (FField f) -> let (nf, nc) = fieldUpdate m f in ({ model | query = fquerySet path (FField nf) model.query }, Cmd.map (Field path) nc)
        _ -> (model, Cmd.none)


view : Model -> Html Msg
view model = div [ class "advsearch" ]
  [ input [ type_ "hidden", id "f", name "f", value <| Maybe.withDefault "" <| Maybe.map (\v -> JE.encode 0 (encodeQuery v)) (fqueryToQuery model.query) ] []
  , div [ class "quickselect" ] <|
    (case model.query of
      FField f -> [Html.map (Field []) (fieldView f)]
      FOr _    -> []
      FAnd l   -> List.indexedMap (\i f -> Html.map (Field [i]) (fieldView f)) <| List.filterMap (\q ->
        case q of
          FField f -> Just f
          _ -> Nothing) l
    ) ++
    --, input [ type_ "button", class "submit", value "Advanced mode" ] [] -- TODO: Advanced mode where you can construct arbitrary queries.
    [ input [ type_ "submit", class "submit", value "Search" ] []
    ]
  , pre []
    [ text <| Maybe.withDefault "" <| Maybe.map (\v -> JE.encode 2 (encodeQuery v)) (fqueryToQuery model.query)
    ]
  ]
