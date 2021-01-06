module AdvSearch.Main exposing (main)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Browser
import Set
import Dict
import Task
import Browser.Dom as Dom
import Array as Array
import Json.Encode as JE
import Json.Decode as JD
import Gen.Api as GApi
import Gen.AdvSearchSave as GASS
import Gen.AdvSearchDel  as GASD
import Gen.AdvSearchLoad as GASL
import Lib.Html exposing (..)
import Lib.Api as Api
import Lib.DropDown as DD
import Lib.Autocomplete as A
import AdvSearch.Lib exposing (..)
import AdvSearch.Fields exposing (..)


main : Program Recv Model Msg
main = Browser.element
  { init   = \e -> (init e, Cmd.none)
  , view   = view
  , update = update
  , subscriptions = \m -> Sub.batch [ DD.sub m.saveDd, Sub.map Field (fieldSub m.query) ]
  }

type alias SQuery = { name: String, query: String }
type alias Recv =
  { uid          : Maybe Int
  , labels       : List { id: Int, label: String }
  , defaultSpoil : Int
  , saved        : List SQuery
  , query        : GApi.ApiAdvSearchQuery
  }

type alias Model =
  { query      : Field
  , qtype      : QType
  , data       : Data
  , saved      : List SQuery
  , saveState  : Api.State
  , saveDd     : DD.Config Msg
  , saveAct    : Int
  , saveName   : String
  , saveDel    : Set.Set String
  }

type Msg
  = Noop
  | Field FieldMsg
  | SaveToggle Bool
  | SaveAct Int
  | SaveName String
  | SaveSave String
  | SaveSaved SQuery GApi.Response
  | SaveLoad String
  | SaveLoaded GApi.Response
  | SaveDelSel String
  | SaveDel (Set.Set String)
  | SaveDeleted (Set.Set String) GApi.Response


-- If the query only contains "quick" selection fields, add the remaining quick fields and sort them.
normalize : QType -> Field -> Data -> (Field, Data)
normalize qtype query odat =
  let quickFromId (n,_,_) = Array.get n fields |> Maybe.map (\f -> abs f.quick) |> Maybe.withDefault 0
      present = List.foldl (\f a -> Set.insert (quickFromId f) a) Set.empty
      defaults pres = Array.foldl (\f (al,dat,an) ->
          if f.qtype == qtype && f.quick > 0 && not (Set.member (abs f.quick) pres)
          then let (ndat, nf) = fieldInit an dat
               in (nf::al, ndat, an+1)
          else (al,dat,an+1)
        ) ([],odat,0) fields
      cmp a b = compare (quickFromId a) (quickFromId b)
  in case query of
      (qid, qdd, FMNest qm) ->
        let pres = present qm.fields
            (nl, ndat, _) = defaults pres
            nqm = { qm | fields = List.sortWith cmp (nl++qm.fields) }
        in if Set.member 0 pres || List.length nqm.fields > 4 then (query, odat) else ((qid, qdd, FMNest nqm), ndat)
      _ -> (query, odat)


loadQuery : Data -> GApi.ApiAdvSearchQuery -> (QType, Field, Data)
loadQuery odat arg =
  let dat = { objid        = 0
            , level        = 0
            , uid          = odat.uid
            , labels       = odat.labels
            , defaultSpoil = odat.defaultSpoil
            , producers    = Dict.union (Dict.fromList <| List.map (\p -> (p.id,p)) <| arg.producers) odat.producers
            , staff        = Dict.union (Dict.fromList <| List.map (\s -> (s.id,s)) <| arg.staff    ) odat.staff
            , tags         = Dict.union (Dict.fromList <| List.map (\t -> (t.id,t)) <| arg.tags     ) odat.tags
            , traits       = Dict.union (Dict.fromList <| List.map (\t -> (t.id,t)) <| arg.traits   ) odat.traits
            , anime        = Dict.union (Dict.fromList <| List.map (\a -> (a.id,a)) <| arg.anime    ) odat.anime
            }
      qtype = if arg.qtype == "v" then V else R

      (dat2, query) = JD.decodeValue decodeQuery arg.query |> Result.toMaybe |> Maybe.withDefault (QAnd []) |> fieldFromQuery qtype dat

      -- We always want the top-level query to be a Nest type.
      addtoplvl = let (_,m) = fieldCreate -1 (Tuple.mapSecond FMNest (nestInit True qtype qtype [query] dat2)) in m
      query2 = case query of
                (_,_,FMNest m) -> if m.qtype == qtype then query else addtoplvl
                _ -> addtoplvl
      dat3 = { dat2 | objid = dat2.objid + 5 } -- +5 for the creation of query2

      (query3, dat4) = normalize qtype query2 dat3
  in (qtype, query3, dat4)


init : Recv -> Model
init arg =
  let dat = { objid        = 0
            , level        = 0
            , uid          = arg.uid
            , labels       = (0, "Unlabeled") :: List.map (\e -> (e.id, e.label)) arg.labels
            , defaultSpoil = arg.defaultSpoil
            , producers    = Dict.empty
            , staff        = Dict.empty
            , tags         = Dict.empty
            , traits       = Dict.empty
            , anime        = Dict.empty
            }
      (qtype, query, ndat) = loadQuery dat arg.query
  in  { query      = query
      , qtype      = qtype
      , data       = ndat
      , saved      = arg.saved
      , saveState  = Api.Normal
      , saveDd     = DD.init "advsearch_save" SaveToggle
      , saveAct    = 0
      , saveName   = ""
      , saveDel    = Set.empty
      }


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    Noop -> (model, Cmd.none)
    Field m ->
      let (ndat, nm, nc) = fieldUpdate model.data m model.query
      in ({ model | data = ndat, query = nm }, Cmd.map Field nc)
    SaveToggle b ->
      let act = if model.saveAct == 0 && not (List.isEmpty model.saved) && fieldToQuery model.data model.query == Nothing then 1 else model.saveAct
      in ( { model | saveDd = DD.toggle model.saveDd b, saveAct = act, saveDel = Set.empty }
         , if b && act == 0 then Task.attempt (always Noop) (Dom.focus "advsearch_saveinput") else Cmd.none)
    SaveAct  n -> ({ model | saveAct  = n, saveDel = Set.empty }, Cmd.none)
    SaveName n -> ({ model | saveName = n }, Cmd.none)
    SaveSave s ->
      case Maybe.map encQuery (fieldToQuery model.data model.query) of
        Just q -> ({ model | saveState = Api.Loading }, GASS.send { name = s, qtype = showQType model.qtype, query = q } (SaveSaved { name = s, query = q }) )
        Nothing -> (model, Cmd.none)
    SaveSaved q GApi.Success ->
      let f rep lst = case lst of
                        (x::xs) ->
                          if x.name == q.name then q :: f True xs
                          else if not rep && x.name > q.name then q :: x :: f True xs
                          else x :: f rep xs
                        [] -> if rep then [] else [q]
      in ({ model | saveState = Api.Normal, saveDd = DD.toggle model.saveDd False, saved = f False model.saved }, Cmd.none)
    SaveSaved _ e -> ({ model | saveState = Api.Error e }, Cmd.none)
    SaveLoad q -> ({ model | saveState = Api.Loading, saveDd = DD.toggle model.saveDd False }, GASL.send { qtype = showQType model.qtype, query = q } SaveLoaded)
    SaveLoaded (GApi.AdvSearchQuery q) ->
      let (_, query, dat) = loadQuery model.data q
      in ({ model | saveState = Api.Normal, query = query, data = dat }, Cmd.none)
    SaveLoaded e -> ({ model | saveState = Api.Error e }, Cmd.none)
    SaveDelSel s -> ({ model | saveDel = (if Set.member s model.saveDel then Set.remove else Set.insert) s model.saveDel }, Cmd.none)
    SaveDel d -> ({ model | saveState = Api.Loading }, GASD.send { qtype = showQType model.qtype, name = Set.toList d } (SaveDeleted d))
    SaveDeleted d GApi.Success -> ({ model | saveState = Api.Normal, saveDel = Set.empty, saved = List.filter (\e -> not (Set.member e.name d)) model.saved }, Cmd.none)
    SaveDeleted _ e -> ({ model | saveState = Api.Error e }, Cmd.none)



view : Model -> Html Msg
view model = div [ class "advsearch" ] <|
  let encQ = Maybe.withDefault "" <| Maybe.map encQuery (fieldToQuery model.data model.query)
  in
  [ input [ type_ "hidden", id "f", name "f", value encQ ] []
  , Html.map Field (fieldView model.data model.query)
  , div [ class "optbuttons" ]
    [ if model.data.uid == Nothing then text "" else div [ class "elm_dd_button" ]
      [ DD.view model.saveDd model.saveState (text "Save/Load") <| \() ->
        [ div [ class "advheader", style "min-width" "300px" ]
          [ div [ class "opts", style "margin-bottom" "5px" ]
            [ if model.saveAct == 0 then b [] [ text "Save"   ] else a [ href "#", onClickD (SaveAct 0) ] [ text "Save" ]
            , if model.saveAct == 1 then b [] [ text "Load"   ] else a [ href "#", onClickD (SaveAct 1) ] [ text "Load" ]
            , if model.saveAct == 2 then b [] [ text "Delete" ] else a [ href "#", onClickD (SaveAct 2) ] [ text "Delete" ]
            , if model.saveAct == 3 then b [] [ text "Default"] else a [ href "#", onClickD (SaveAct 3) ] [ text "Default" ]
            ]
          , h3 [] [ text <| if model.saveAct == 0 then "Save current filter" else if model.saveAct == 1 then "Load filter" else "Delete saved filter" ]
          ]
        , case (List.filter (\e -> e.name /= "") model.saved, model.saveAct) of
            (_, 0) ->
              if encQ == "" then text "Nothing to save." else
              form_ "" (SaveSave model.saveName) False
              [ inputText "advsearch_saveinput" model.saveName SaveName [ required True, maxlength 50, placeholder "Name...", style "width" "290px" ]
              , if model.saveName /= "" && List.any (\e -> e.name == model.saveName) model.saved
                then text "You already have a filter by that name, click save to overwrite it."
                else text ""
              , submitButton "Save" model.saveState True
              ]
            (_, 3) ->
              div []
              [ p [ class "center", style "padding" "0px 5px" ]
                [ text "You can set a default filter that will be applied automatically to most listings on the site,"
                , text " this includes the \"Random visual novel\" button, lists on the homepage, tag pages, etc."
                , text " This feature is mainly useful to filter out tags, languages or platforms that you are not interested in seeing."
                ]
              , br [] []
              , case List.filter (\e -> e.name == "") model.saved of
                  [d] -> span []
                         [ inputButton "Load my default filters" (SaveLoad d.query) [style "width" "100%"]
                         , br [] []
                         , br [] []
                         , inputButton "Delete my default filters" (SaveDel (Set.fromList [""])) [style "width" "100%"]
                         ]
                  _ -> text "You don't have a default filter set."
              , if encQ /= "" then inputButton "Save current filters as default" (SaveSave "") [ style "width" "100%" ] else text ""
              ]
            ([], _) -> text "You don't have any saved queries."
            (l, 1) ->
              div []
              [ if encQ == "" || List.any (\e -> encQ == e.query) l
                then text "" else text "Unsaved changes will be lost when loading a saved filter."
              , ul [] <| List.map (\e -> li [ style "overflow" "hidden", style "text-overflow" "ellipsis" ] [ a [ href "#", onClickD (SaveLoad e.query) ] [ text e.name ] ]) l
              ]
            (l, _) ->
              div []
              [ ul [] <| List.map (\e -> li [ style "overflow" "hidden", style "text-overflow" "ellipsis" ] [ linkRadio (Set.member e.name model.saveDel) (always (SaveDelSel e.name)) [ text e.name ] ]) l
              , inputButton "Delete selected" (SaveDel model.saveDel) [ disabled (Set.isEmpty model.saveDel) ]
              ]
        ]
      ]
    , input [ type_ "submit", class "submit", value "Search" ] []
    ]
  ]
