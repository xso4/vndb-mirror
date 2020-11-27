module AdvSearch.Main exposing (main)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Browser
import Set
import Dict
import Array as A
import Json.Encode as JE
import Json.Decode as JD
import Gen.Api as GApi
import AdvSearch.Query exposing (..)
import AdvSearch.Fields exposing (..)


main : Program Recv Model Msg
main = Browser.element
  { init   = \e -> (init e, Cmd.none)
  , view   = view
  , update = update
  , subscriptions = \m -> Sub.map Field (fieldSub m.query)
  }

type alias Recv =
  { query        : JE.Value
  , qtype        : String
  , defaultSpoil : Int
  , producers    : List GApi.ApiProducerResult
  , tags         : List GApi.ApiTagResult
  , traits       : List GApi.ApiTraitResult
  }

type alias Model =
  { query : Field
  , qtype : QType
  , data  : Data
  }

type Msg
  = Field FieldMsg


-- Add default set of fields (if they aren't present yet) and sort the list
normalize : Model -> Model
normalize model =
  let present = List.foldl (\(n,_,_) a -> Set.insert n a) Set.empty
      defaults pres = A.foldl (\f (al,dat,an) ->
          if f.qtype == model.qtype && f.quick /= Nothing && not (Set.member an pres)
          then let (ndat, nf) = fieldInit an dat
               in (nf::al, ndat, an+1)
          else (al,dat,an+1)
        ) ([],model.data,0) fields
      cmp (an,add,am) (bn,bdd,bm) = -- Sort active filters before empty ones, then order by 'quick', fallback to title
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
  in case model.query of
      (qid, qdd, FMNest qm) ->
        let (nl, dat, _) = defaults (present qm.fields)
            nqm = { qm | fields = List.sortWith cmp (nl++qm.fields) }
        in { model | query = (qid, qdd, FMNest nqm), data = dat }
      _ -> model


init : Recv -> Model
init arg =
  let dat = { objid        = 0
            , level        = 0
            , defaultSpoil = arg.defaultSpoil
            , producers    = Dict.fromList <| List.map (\p -> (p.id,p)) <| arg.producers
            , tags         = Dict.fromList <| List.map (\t -> (t.id,t)) <| arg.tags
            , traits       = Dict.fromList <| List.map (\t -> (t.id,t)) <| arg.traits
            }
      qtype = if arg.qtype == "v" then V else R

      (ndat, query) = JD.decodeValue decodeQuery arg.query |> Result.toMaybe |> Maybe.withDefault (QAnd []) |> fieldFromQuery qtype dat

      -- We always want the top-level query to be a Nest type.
      addtoplvl = let (_,m) = fieldCreate -1 (Tuple.mapSecond FMNest (nestInit NAnd qtype [query] ndat)) in m
      nquery = case query of
                (_,_,FMNest m) -> if m.ntype == NAnd || m.ntype == NOr then query else addtoplvl
                _ -> addtoplvl

      -- Is this a "simple" query? i.e. one that consists of at most a single level of nesting
      isSimple = case nquery of
                  (_,_,FMNest m) -> List.all (\f -> case f of
                                                      (_,_,FMNest _) -> False
                                                      _ -> True) m.fields
                  _ -> True

      model = { query = nquery
              , qtype = qtype
              , data  = { ndat | objid = ndat.objid + 5 } -- +5 for the creation of nQuery
              }
  in if isSimple then normalize model else model


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    Field m ->
      let (ndat, nm, nc) = fieldUpdate model.data m model.query
      in ({ model | data = ndat, query = nm }, Cmd.map Field nc)


view : Model -> Html Msg
view model = div [ class "advsearch" ]
  [ input [ type_ "hidden", id "f", name "f", value <| Maybe.withDefault "" <| Maybe.map encQuery (fieldToQuery model.query) ] []
  , Html.map Field (nestFieldView model.data model.query)
  , input [ type_ "submit", class "submit", value "Search" ] []
  ]
