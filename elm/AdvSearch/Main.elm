module AdvSearch.Main exposing (main)

-- TODO: This is a quick'n'dirty proof of concept, most of the functionality in
-- here needs to be abstracted so that we can query more than just the
-- language field.

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Browser
import Set
import Json.Encode as JE
import Json.Decode as JD
import Lib.DropDown as DD
import Lib.Api as Api
import Lib.Html exposing (..)
import Lib.Util exposing (..)
import Gen.Types as GT
import AdvSearch.Query exposing (..)

main : Program JE.Value Model Msg
main = Browser.element
  { init   = \e -> (init e, Cmd.none)
  , view   = view
  , update = update
  , subscriptions = \m -> DD.sub m.langDd
  }


type alias Model =
  { lang    : SetModel String
  , langDd  : DD.Config Msg
  }


init : JE.Value -> Model
init arg =
  let m = { lang     = setInit
          , langDd   = DD.init "adv_lang" LangToggle
          }
      langFromQuery = setFromQuery (\q -> case q of
                                           QStr "lang" op v -> Just (op, v)
                                           _ -> Nothing)
  in JD.decodeValue decodeQuery arg |> Result.toMaybe |> Maybe.andThen langFromQuery |> Maybe.map (\l -> { m | lang = l }) |> Maybe.withDefault m


modelToQuery : Model -> Maybe Query
modelToQuery m = setToQuery (QStr "lang") m.lang


type Msg
  = LangToggle Bool
  | Lang (SetMsg String)

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    LangToggle b -> ({ model | langDd = DD.toggle model.langDd b }, Cmd.none)
    Lang m       -> ({ model | lang = setUpdate m model.lang }, Cmd.none)


view : Model -> Html Msg
view model = div [ class "advsearch" ]
  [ input [ type_ "hidden", id "f", name "f", value <| Maybe.withDefault "" <| Maybe.map (\v -> JE.encode 0 (encodeQuery v)) (modelToQuery model) ] []
  , div [ class "quickselect" ]
    [ div [ class "elm_dd_input" ]
      [ DD.view model.langDd Api.Normal
        (case Set.size model.lang.sel of
          0 -> b [ class "grayedout" ] [ text "Language" ]
          1 -> text <| Maybe.withDefault "" <| lookup (Set.toList model.lang.sel |> List.head |> Maybe.withDefault "") GT.languages
          n -> text <| "Language (" ++ String.fromInt n ++ ")")
         <| \() ->
           [ div [ class "advopts" ]
             [ a [ href "#", onClickD (Lang SetMode) ] [ text <| "Mode:" ++ if model.lang.single then "single" else if model.lang.and then "and" else "or" ]
             , linkRadio model.lang.neg (Lang<<SetNeg) [ text "invert" ] -- XXX: Not sure it's obvious what this does, not sure how to improve either
             ]
           , ul [ style "columns" "2"] <| List.map (\(l,t) -> li [] [ linkRadio (Set.member l model.lang.sel) (Lang << SetSel l) [ langIcon l, text t ] ]) GT.languages
           ]
      ]
    --, input [ type_ "button", class "submit", value "Advanced mode" ] [] -- TODO: Advanced mode where you can construct arbitrary queries.
    , input [ type_ "submit", class "submit", value "Search" ] []
    ]
  , pre []
    [ text <| Maybe.withDefault "" <| Maybe.map (\v -> JE.encode 2 (encodeQuery v)) (modelToQuery model)
    ]
  ]
