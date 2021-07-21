-- TODO: Integrate this with UList.VNPage and have this replace UList.Opt.
-- XXX: Only one widget can be instantiated per VN on a single page.
module UList.Widget exposing (main)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Browser
import Task
import Process
import Set
import Date
import Dict exposing (Dict)
import Lib.Util exposing (..)
import Lib.Html exposing (..)
import Lib.Ffi as Ffi
import Lib.Api as Api
import Lib.RDate as RDate
import Lib.DropDown as DD
import Gen.Api as GApi
import Gen.UListWidget as UW
import Gen.UListVNNotes as GVN
import Gen.UListDel as GDE
import UList.LabelEdit as LE
import UList.VoteEdit as VE
import UList.DateEdit as DE
import UList.ReleaseEdit as RE


main : Program UW.Recv Model Msg
main = Browser.element
  { init = \f -> (init f, Date.today |> Task.perform Today)
  , subscriptions = \m -> if not m.open then Sub.none else Sub.batch <|
      [ DD.onClickOutside "ulist-widget-box" (Open False)
      , Sub.map Label (DD.sub m.labels.dd)
      , Sub.map Vote  (DD.sub m.vote.dd)
      ] ++ List.map (\r -> Sub.map (Rel r.rid) (DD.sub r.dd)) m.rels
  , view = view
  , update = update
  }

type alias Model =
  { uid        : String
  , vid        : String
  , loadState  : Api.State
  , today      : Date.Date
  , title      : Maybe String -- Nothing is used here to indicate that we haven't loaded the full data yet.
  , open       : Bool
  , onlist     : Bool
  , del        : Bool
  , labels     : LE.Model
  , vote       : VE.Model
  , canvote    : Bool
  , canreview  : Bool
  , review     : Maybe String
  , notes      : String
  , notesRev   : Int
  , notesSaved : String
  , notesState : Api.State
  , started    : DE.Model
  , finished   : DE.Model
  , rels       : List RE.Model
  , relNfo     : Dict String GApi.ApiReleases
  , relOptions : List (String, String)
  }

init : UW.Recv -> Model
init f =
  { uid       = f.uid
  , vid       = f.vid
  , loadState = Api.Normal
  , today     = Date.fromOrdinalDate 2100 1
  , title     = Maybe.map (\full -> full.title) f.full
  , open      = False
  , onlist    = f.labels /= Nothing
  , del       = False
    -- TODO: LabelEdit and VoteEdit create an internal vid-based ID, so this widget can't be used on VN pages or UList listings. Need to fix that.
  , labels    = LE.init
    { uid       = f.uid
    , vid       = f.vid
    , selected  = List.map (\l -> l.id) (Maybe.withDefault [] f.labels)
    , labels    = Maybe.withDefault
                    (List.map (\l -> {id = l.id, label = l.label, private = True}) (Maybe.withDefault [] f.labels))
                    (Maybe.map (\full -> full.labels) f.full)
    }
  , vote       = VE.init { uid = f.uid, vid = f.vid, vote = Maybe.andThen (\full -> full.vote) f.full }
  , canvote    = Maybe.map (\full -> full.canvote   ) f.full |> Maybe.withDefault False
  , canreview  = Maybe.map (\full -> full.canreview ) f.full |> Maybe.withDefault False
  , review     = Maybe.andThen (\full -> full.review) f.full
  , notes      = Maybe.map (\full -> full.notes     ) f.full |> Maybe.withDefault ""
  , notesRev   = 0
  , notesSaved = Maybe.map (\full -> full.notes     ) f.full |> Maybe.withDefault ""
  , notesState = Api.Normal
  , started    = let m = DE.init { uid = f.uid, vid = f.vid, date = Maybe.map (\full -> full.started ) f.full |> Maybe.withDefault "", start = True  } in { m | visible = True }
  , finished   = let m = DE.init { uid = f.uid, vid = f.vid, date = Maybe.map (\full -> full.finished) f.full |> Maybe.withDefault "", start = False } in { m | visible = True }
  , rels       = List.map (\st -> RE.init ("widget-" ++ f.vid) { uid = f.uid, rid = st.id, status = Just st.status, empty = "" }) <| Maybe.withDefault [] <| Maybe.map (\full -> full.rlist) f.full
  , relNfo     = Dict.fromList <| List.map (\r -> (r.id, r)) <| Maybe.withDefault [] <| Maybe.map (\full -> full.releases) f.full
  , relOptions = Maybe.withDefault [] <| Maybe.map (\full -> List.map (\r -> (r.id, showrel r)) full.releases) f.full
  }


type Msg
  = Today Date.Date
  | Open Bool
  | Loaded GApi.Response
  | Label LE.Msg
  | Vote VE.Msg
  | Notes String
  | NotesSave Int
  | NotesSaved Int GApi.Response
  | Started DE.Msg
  | Finished DE.Msg
  | Del Bool
  | Delete
  | Deleted GApi.Response
  | Rel String RE.Msg
  | RelAdd String


setOnList : Model -> Model
setOnList model =
  { model | onlist = model.onlist
                  || model.vote.ovote /= Nothing
                  || not (Set.isEmpty model.labels.sel)
                  || model.notes /= ""
                  || model.started.val /= ""
                  || model.finished.val /= ""
                  || not (List.isEmpty model.rels)
  }


isPublic : Model -> Bool
isPublic model =
     LE.isPublic model.labels
  || (isJust model.vote.vote && List.any (\l -> l.id == 7 && not l.private) model.labels.labels)


showrel : GApi.ApiReleases -> String
showrel r = "[" ++ (RDate.format (RDate.expand r.released)) ++ " " ++ (String.join "," r.lang) ++ "] " ++ r.title ++ " (" ++ r.id ++ ")"


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    Today d -> ({ model | today = d }, Cmd.none)
    Open b ->
      if b && model.title == Nothing
      then ({ model | open = b, loadState = Api.Loading }, UW.send { uid = model.uid, vid = model.vid } Loaded)
      else ({ model | open = b }, Cmd.none)

    Loaded (GApi.UListWidget w) -> let m = init w in ({ m | open = True }, Cmd.none)
    Loaded e -> ({ model | loadState = Api.Error e }, Cmd.none)

    Label    m -> let (nm, nc) = LE.update m model.labels   in (setOnList { model | labels   = nm }, Cmd.map Label    nc)
    Vote     m -> let (nm, nc) = VE.update m model.vote     in (setOnList { model | vote     = nm }, Cmd.map Vote     nc)
    Started  m -> let (nm, nc) = DE.update m model.started  in (setOnList { model | started  = nm }, Cmd.map Started  nc)
    Finished m -> let (nm, nc) = DE.update m model.finished in (setOnList { model | finished = nm }, Cmd.map Finished nc)

    Notes s ->
      ( { model | notes = s, notesRev = model.notesRev + 1 }
      , Task.perform (\_ -> NotesSave (model.notesRev+1)) <| Process.sleep 1000)
    NotesSave rev ->
      if rev /= model.notesRev || model.notes == model.notesSaved
      then (model, Cmd.none)
      else ( { model | notesState = Api.Loading }
           , GVN.send { uid = model.uid, vid = model.vid, notes = model.notes } (NotesSaved rev))
    NotesSaved rev GApi.Success ->
      if model.notesRev /= rev
      then (model, Cmd.none)
      else (setOnList {model | notesSaved = model.notes, notesState = Api.Normal }, Cmd.none)
    NotesSaved _ e -> ({ model | notesState = Api.Error e }, Cmd.none)

    Del b -> ({ model | del = b }, Cmd.none)
    Delete -> ({ model | loadState = Api.Loading }, GDE.send { uid = model.uid, vid = model.vid } Deleted)
    Deleted GApi.Success -> (init { uid = model.uid, vid = model.vid, labels = Nothing, full = Nothing }, Cmd.none)
    Deleted e -> ({ model | loadState = Api.Error e }, Cmd.none)

    Rel rid m ->
      case List.filterMap (\r -> if r.rid == rid then Just (RE.update m r) else Nothing) model.rels |> List.head of
        Nothing -> (model, Cmd.none)
        Just (rm, rc) ->
          let
            nr = if rm.state == Api.Normal && rm.status == Nothing
                 then List.filter (\r -> r.rid /= rid) model.rels
                 else List.map (\r -> if r.rid == rid then rm else r) model.rels
          in ({ model | rels = nr }, Cmd.map (Rel rid) rc)
    RelAdd rid ->
      ( setOnList { model | rels = model.rels ++ (if rid == "" then [] else [RE.init model.vid { rid = rid, uid = model.uid, status = Just 2, empty = "" }]) }
      , Task.perform (always <| Rel rid <| RE.Set (Just 2) True) <| Task.succeed True)


view : Model -> Html Msg
view model =
  let
    icon () =
      let fn = if not model.onlist then "add"
               else List.range 1 6
                 |> List.filter (\n -> Set.member n model.labels.tsel)
                 |> List.maximum
                 |> Maybe.map (\n -> "l" ++ String.fromInt n)
                 |> Maybe.withDefault "unknown"
          lbl = if not model.onlist then "Add to list"
                else String.join ", " <| List.filterMap (\l -> if Set.member l.id model.labels.tsel && l.id /= 7 then Just l.label else Nothing) model.labels.labels
      in img [ src (Ffi.urlStatic ++ "/f/list-" ++ fn ++ ".svg"), class ("ulist-widget-icon liststatus_icon "++fn), title lbl, onClickN (Open True) ] []

    rel r =
      case Dict.get r.rid model.relNfo of
        Nothing -> text ""
        Just nfo -> relnfo r nfo

    relnfo r nfo =
      tr []
      [ td [ class "tco1" ] [ Html.map (Rel r.rid) (RE.view r) ]
      , td [ class "tco2" ] [ RDate.display model.today nfo.released ]
      , td [ class "tco3" ]
        <| List.map platformIcon nfo.platforms
        ++ List.map langIcon nfo.lang
        ++ [ releaseTypeIcon nfo.rtype ]
      , td [ class "tco4" ] [ a [ href ("/"++nfo.id), title nfo.original ] [ text nfo.title ] ]
      ]

    box () =
      [ h2 [] [ text (Maybe.withDefault "" model.title) ]
      , div [ style "text-align" "right", style "margin" "3px 0" ] <|
        case (model.del, model.onlist) of
          ( _, False) -> [ b [ class "grayedout" ] [ text "not on your list" ] ]
          (True, _) ->
            [ a [ onClickD Delete ] [ text "Yes, delete" ]
            , text " | "
            , a [ onClickD (Del False) ] [ text "Cancel" ]
            ]
          (False, True) ->
            [ span [ classList [("hidden", not (isPublic model))], title "This visual novel is on your public list" ] [ text "👁 " ]
            , text "On your list | "
            , a [ onClickD (Del True) ] [ text "Remove from list" ]
            ]
      , table []
        [ tr [] [ td [] [ text "Labels" ], td [] [ Html.map Label (LE.view model.labels "- select label -") ] ]
        , if not model.canvote then text "" else
          tr []
          [ td [] [ text "Vote" ]
          , td []
            [ div [ style "width" "80px", style "display" "inline-block" ] [ Html.map Vote (VE.view model.vote "- vote -") ]
            , case (model.vote.vote /= Nothing && model.canreview, model.review) of
                 (False, _)  -> text ""
                 (True, Nothing) -> a [ href ("/" ++ model.vid ++ "/addreview") ] [ text " write a review »" ]
                 (True, Just w)  -> a [ href ("/" ++ w ++ "/edit") ] [ text " edit review »" ]
            ]
          ]
        , tr [] [ td [] [ text "Start date"  ], td [ class "date" ] [ Html.map Started  (DE.view model.started ) ] ]
        , tr [] [ td [] [ text "Finish date" ], td [ class "date" ] [ Html.map Finished (DE.view model.finished) ] ]
        , tr []
          [ td [] [ text "Notes ", span [ class "spinner", classList [("hidden", model.notesState /= Api.Loading)] ] [] ]
          , td [] <|
            [ textarea ([ rows 2, cols 40, onInput Notes, onBlur (NotesSave model.notesRev)] ++ GVN.valNotes) [ text model.notes ]
            ] ++ case model.notesState of
                   Api.Error e -> [ br [] [], b [ class "standout" ] [ text <| Api.showResponse e ] ]
                   _ -> []
          ]
        ]
      , if List.isEmpty model.relOptions then text "" else h2 [] [ text "Releases" ]
      , table [] <|
        (if List.isEmpty model.relOptions then text "" else tfoot [] [ tr []
          [ td [] []
          , td [ colspan 3 ]
            [ inputSelect "" "" RelAdd [] <| ("", "-- add release --") :: List.filter (\(rid,_) -> not <| List.any (\r -> r.rid == rid) model.rels) model.relOptions ]
          ] ]
        ) :: List.map rel model.rels
      ]
  in
    if model.open
    then div [ class "ulist-widget elm_dd_input" ]
         [ div [ id "ulist-widget-box" ] <|
           case model.loadState of
             Api.Loading -> [ div [ class "spinner" ] [] ]
             Api.Error e -> [ b [ class "standout" ] [ text <| Api.showResponse e ] ]
             Api.Normal -> box () ]
    else icon ()
