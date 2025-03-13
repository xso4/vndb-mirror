port module UList.Opt exposing (main)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Task
import Process
import Browser
import Date
import Dict exposing (Dict)
import Lib.Util exposing (..)
import Lib.Html exposing (..)
import Lib.Api as Api
import Lib.RDate as RDate
import Lib.DropDown as DD
import UList.ReleaseEdit as RE
import Gen.Types as T
import Gen.Api as GApi
import Gen.UListVNNotes as GVN
import Gen.UListDel as GDE
import Gen.Release as GR

--main : Program GVN.Recv Model Msg
--main = Browser.element
  { init = \f -> (init f, Date.today |> Task.perform Today)
  , subscriptions = \model -> List.map (\r -> Sub.map (Rel r.rid) (DD.sub r.dd)) model.rels |> Sub.batch
  , view = view
  , update = update
  }

port ulistVNDeleted : Bool -> Cmd msg
port ulistNotesChanged : String -> Cmd msg
port ulistRelChanged : (Int, Int) -> Cmd msg

type alias Model =
  { flags      : GVN.Recv
  , today      : Date.Date
  , del        : Bool
  , delState   : Api.State
  , notes      : String
  , notesRev   : Int
  , notesState : Api.State
  , rels       : List RE.Model
  , relNfo     : Dict String GApi.ApiReleases
  , relOptions : Maybe (List (String, String))
  , relState   : Api.State
  }

init : GVN.Recv -> Model
init f =
  { flags      = f
  , today      = Date.fromOrdinalDate 2100 1
  , del        = False
  , delState   = Api.Normal
  , notes      = f.notes
  , notesRev   = 0
  , notesState = Api.Normal
  , rels       = List.map2 (\st nfo -> RE.init f.vid { rid = nfo.id, status = Just st, empty = "" }) f.relstatus f.rels
  , relNfo     = Dict.fromList <| List.map (\r -> (r.id, r)) f.rels
  , relOptions = Nothing
  , relState   = Api.Normal
  }

type Msg
  = Today Date.Date
  | Del Bool
  | Delete
  | Deleted GApi.Response
  | Notes String
  | NotesSave Int
  | NotesSaved Int GApi.Response
  | Rel String RE.Msg
  | RelLoad
  | RelLoaded GApi.Response
  | RelAdd String


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    Today d -> ({ model | today = d }, Cmd.none)

    Del b -> ({ model | del = b }, Cmd.none)
    Delete ->
      ( { model | delState = Api.Loading }
      , GDE.send { vid = model.flags.vid } Deleted)
    Deleted GApi.Success -> (model, ulistVNDeleted True)
    Deleted e -> ({ model | delState = Api.Error e }, Cmd.none)

    Notes s ->
      ( { model | notes = s, notesRev = model.notesRev + 1 }
      , Task.perform (\_ -> NotesSave (model.notesRev+1)) <| Process.sleep 1000)
    NotesSave rev ->
      if rev /= model.notesRev || model.notes == model.flags.notes
      then (model, Cmd.none)
      else ( { model | notesState = Api.Loading }
           , GVN.send { vid = model.flags.vid, notes = model.notes } (NotesSaved rev))
    NotesSaved rev GApi.Success ->
      let f = model.flags
          nf = { f | notes = model.notes }
       in if model.notesRev /= rev
          then (model, Cmd.none)
          else ({model | flags = nf, notesState = Api.Normal }, ulistNotesChanged model.notes)
    NotesSaved _ e -> ({ model | notesState = Api.Error e }, Cmd.none)

    Rel rid m ->
      case List.filterMap (\r -> if r.rid == rid then Just (RE.update m r) else Nothing) model.rels |> List.head of
        Nothing -> (model, Cmd.none)
        Just (rm, rc) ->
          let
            nr = if rm.state == Api.Normal && rm.status == Nothing
                 then List.filter (\r -> r.rid /= rid) model.rels
                 else List.map (\r -> if r.rid == rid then rm else r) model.rels
            nm = { model | rels = nr }
            nc = Cmd.batch
                 [ Cmd.map (Rel rid) rc
                 , ulistRelChanged (List.length <| List.filter (\r -> r.status == Just 2) nr, List.length nr) ]
          in (nm, nc)

    RelLoad ->
      ( { model | relState = Api.Loading }
      , GR.send { vid = model.flags.vid } RelLoaded )
    RelLoaded (GApi.Releases rels) ->
      ( { model
        | relState = Api.Normal
        , relNfo = Dict.union (Dict.fromList <| List.map (\r -> (r.id, r)) rels) model.relNfo
        , relOptions = Just <| List.map (\r -> (r.id, RDate.showrel r)) rels
        }, Cmd.none)
    RelLoaded e -> ({ model | relState = Api.Error e }, Cmd.none)
    RelAdd rid ->
      ( { model | rels = model.rels ++ (if rid == "" then [] else [RE.init model.flags.vid { rid = rid, status = Just 2, empty = "" }]) }
      , Task.perform (always <| Rel rid <| RE.Set (Just 2) True) <| Task.succeed True)


view : Model -> Html Msg
view model =
  let
    opt =
      [ tr []
        [ td [ colspan 5 ]
          [ textarea (
              [ placeholder "Notes", rows 2, cols 80
              , onInput Notes, onBlur (NotesSave model.notesRev)
              , maxlength 2000
              ]
            ) [ text model.notes ]
          , div [ ] <|
            [ div [ class "spinner", classList [("hidden", model.notesState /= Api.Loading)] ] []
            , a [ href "#", onClickD (Del True) ] [ text "Remove VN" ]
            ] ++ (
              if model.relOptions == Nothing
              then [ text " | ", a [ href "#", onClickD RelLoad ] [ text "Add release" ] ]
              else []
            ) ++ (
              case model.notesState of
                Api.Error e -> [ br [] [], b [] [ text <| Api.showResponse e ] ]
                _ -> []
            )
          ]
        ]
      , if model.relOptions == Nothing && model.relState == Api.Normal
        then text ""
        else tfoot []
        [ tr []
          [ td [ colspan 5 ] <|
            -- TODO: This <select> solution is ugly as hell, a Lib.DropDown-based solution would be nicer.
            -- Or just throw all releases in the table and use the status field for add stuff.
            case (model.relOptions, model.relState) of
              (Just opts, _)   -> [ inputSelect "" "" RelAdd [ style "width" "500px" ]
                                    <| ("", "-- add release --") :: List.filter (\(rid,_) -> not <| List.any (\r -> r.rid == rid) model.rels) opts ]
              (_, Api.Normal)  -> []
              (_, Api.Loading) -> [ span [ class "spinner" ] [], text "Loading releases..." ]
              (_, Api.Error e) -> [ b [] [ text <| Api.showResponse e ], text ". ", a [ href "#", onClickD RelLoad ] [ text "Try again" ] ]
          ]
        ]
      ]

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
      , td [ class "tco4" ] [ a [ href ("/"++nfo.id), title nfo.alttitle ] [ text nfo.title ] ]
      ]

    confirm =
      div []
      [ text "Are you sure you want to remove this visual novel from your list? "
      , a [ onClickD Delete ] [ text "Yes" ]
      , text " | "
      , a [ onClickD (Del False) ] [ text "Cancel" ]
      ]

  in case (model.del, model.delState) of
      (False, _) -> table [] <| (if model.flags.own then opt else []) ++ List.map rel model.rels
      (_, Api.Normal)  -> confirm
      (_, Api.Loading) -> div [ class "spinner" ] []
      (_, Api.Error e) -> b [] [ text <| "Error removing item: " ++ Api.showResponse e ]
