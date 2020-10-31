module AdvSearch.Main exposing (main)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Browser
import Set
import Array as A
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
  , ftype : FieldType
  , ddid  : Int
  }

type Msg
  = Field (List Int) FieldMsg


-- Add "default" set of filters if they aren't present yet and sort the list
normalizeForQuick : Model -> Model
normalizeForQuick model =
  let present = List.foldr (\f a ->
          case f of
            FField (n,_,_) -> Set.insert n a
            _ -> a
        ) Set.empty
      defaults pres = A.foldl (\f (al,did,an) ->
          if f.ftype == model.ftype && f.quick /= Nothing && not (Set.member an pres)
          then (FField (fieldInit an did) :: al, did+1, an+1)
          else (al,did,an+1)
        ) ([],model.ddid,0) fields
      cmp a b =
        case (a,b) of -- Sort active filters before empty ones, then order by 'quick', fallback to title
          (FField (an,add,am), FField (bn,bdd,bm)) ->
            let aq = fieldToQuery (an,add,am) /= Nothing
                bq = fieldToQuery (bn,bdd,bm) /= Nothing
                af = A.get an fields
                bf = A.get bn fields
                ao = Maybe.andThen (\d -> d.quick) af |> Maybe.withDefault 9999
                bo = Maybe.andThen (\d -> d.quick) bf |> Maybe.withDefault 9999
                at = Maybe.map (\d -> d.title) af |> Maybe.withDefault ""
                bt = Maybe.map (\d -> d.title) bf |> Maybe.withDefault ""
            in if aq && not bq then LT else if not aq && bq then GT
               else if ao /= bo then compare ao bo else compare at bt
          _ -> EQ
      norm l =
        let (nl,did,_) = defaults (present l)
        in { model | query = FAnd (List.sortWith cmp (nl++l)), ddid = did }
  in case model.query of
      FAnd   l -> norm l
      FField f -> norm [FField f]
      _ -> model


init : JE.Value -> Model
init arg =
  let (ddid, query) = JD.decodeValue decodeQuery arg |> Result.toMaybe |> Maybe.map (fqueryFromQuery V 1) |> Maybe.withDefault (0, FAnd [])
  in normalizeForQuick
  { query = query
  , ftype = V
  , ddid  = ddid
  }


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
  ]
