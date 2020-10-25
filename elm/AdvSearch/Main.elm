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
  { langSel  : Set.Set String
  , langDd   : DD.Config Msg
  , langAnd  : Bool
  , langNeg  : Bool
  }


init : JE.Value -> Model
init v = JD.decodeValue decodeQuery v |> Result.toMaybe |> Maybe.andThen query2Model |> Maybe.withDefault
  { langSel  = Set.empty
  , langDd   = DD.init "adv_lang" LangToggle
  , langAnd  = False
  , langNeg  = False
  }


model2Query : Model -> Maybe Query
model2Query m =
  case (m.langNeg, m.langAnd, Set.toList m.langSel) of
    (_,_,[])  -> Nothing
    (n,_,[v]) -> Just <| QStr "lang" (if n then Ne else Eq) v
    (False, False, l) -> Just <| QOr  <| List.map (\v -> QStr "lang" Eq v) l
    (True , False, l) -> Just <| QAnd <| List.map (\v -> QStr "lang" Ne v) l
    (False, True , l) -> Just <| QAnd <| List.map (\v -> QStr "lang" Eq v) l
    (True , True , l) -> Just <| QOr  <| List.map (\v -> QStr "lang" Ne v) l


-- Only recognizes queries generated with model2Query, doesn't handle alternative query structures.
query2Model : Query -> Maybe Model
query2Model q =
  let m and neg l = Just { langSel = Set.fromList l, langAnd = xor neg and, langNeg = neg, langDd = DD.init "adv_lang" LangToggle }
      single and qs =
        case qs of
          QStr "lang" Eq v -> m and False [v]
          QStr "lang" Ne v -> m and True  [v]
          _ -> Nothing
      lst and qs xqs =
        case (qs, xqs) of
          (_, []) -> single and qs
          (QStr "lang" op _, QStr "lang" opn v :: xs) -> if op /= opn then Nothing else Maybe.map (\model -> { model | langSel = Set.insert v model.langSel }) (lst and qs xs)
          _ -> Nothing
  in case q of
      QAnd (x::xs) -> lst True  x xs
      QOr  (x::xs) -> lst False x xs
      _ -> single False q


type Msg
  = LangToggle Bool
  | LangSel String Bool
  | LangAnd Bool
  | LangNeg Bool

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    LangToggle b -> ({ model | langDd = DD.toggle model.langDd b }, Cmd.none)
    LangSel s b  -> ({ model | langSel = if b then Set.insert s model.langSel else Set.remove s model.langSel }, Cmd.none)
    LangAnd b    -> ({ model | langAnd = b }, Cmd.none)
    LangNeg b    -> ({ model | langNeg = b }, Cmd.none)


view : Model -> Html Msg
view model = div [ class "advsearch" ]
  [ input [ type_ "hidden", id "f", name "f", value <| Maybe.withDefault "" <| Maybe.map (\v -> JE.encode 0 (encodeQuery v)) (model2Query model) ] []
  , div [ class "quickselect" ]
    [ div [ class "elm_dd_input" ]
      [ DD.view model.langDd Api.Normal
        (case Set.size model.langSel of
          0 -> b [ class "grayedout" ] [ text "Language" ]
          1 -> text <| Maybe.withDefault "" <| lookup (Set.toList model.langSel |> List.head |> Maybe.withDefault "") GT.languages
          n -> text <| "Language (" ++ String.fromInt n ++ ")")
         <| \() -> -- TODO: Styling & single-selection mode
           [ div []
             [ linkRadio model.langAnd LangAnd [ text "and" ]
             , text " / "
             , linkRadio (not model.langAnd) (\b -> LangAnd (not b)) [ text "or" ]
             ]
           , div []
             [ linkRadio (not model.langNeg) (\b -> LangNeg (not b)) [ text "include" ]
             , text " / "
             , linkRadio model.langNeg LangNeg [ text "exclude" ]
             ]
           , ul [ style "columns" "2"] <| List.map (\(l,t) -> li [] [ linkRadio (Set.member l model.langSel) (LangSel l) [ langIcon l, text t ] ]) GT.languages
           ]
      ]
    , input [ type_ "button", class "submit", value "Advanced mode" ] [] -- TODO: Advanced mode where you can construct arbitrary queries.
    , input [ type_ "submit", class "submit", value "Search" ] []
    ]
  , pre []
    [ text <| Maybe.withDefault "" <| Maybe.map (\v -> JE.encode 2 (encodeQuery v)) (model2Query model)
    , br [] [], br [] []
    , text <| Maybe.withDefault "" <| Maybe.map (\v -> JE.encode 2 (encodeQuery v)) <| Maybe.andThen (\nm -> model2Query nm) <| Maybe.andThen (\q -> query2Model q) (model2Query model)
    ]
  ]
