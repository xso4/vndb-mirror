port module UList.LabelEdit exposing (main, init, update, view, isPublic, Model, Msg)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Browser
import Task
import Set exposing (Set)
import Dict exposing (Dict)
import Lib.Util exposing (..)
import Lib.Html exposing (..)
import Lib.Api as Api
import Lib.DropDown as DD
import Gen.Api as GApi
import Gen.UListLabelAdd as GLA
import Gen.UListLabelEdit as GLE


main : Program GLE.Recv Model Msg
main = Browser.element
  { init = \f -> (init f, Cmd.none)
  , subscriptions = \model -> DD.sub model.dd
  , view = \m -> view m "-"
  , update = update
  }

port ulistLabelChanged : Bool -> Cmd msg

type alias Model =
  { uid      : String
  , vid      : String
  , labels   : List GLE.RecvLabels
  , sel      : Set Int -- Set of label IDs applied on the server
  , tsel     : Set Int -- Set of label IDs applied on the client
  , state    : Dict Int Api.State -- Only for labels that are being changed
  , dd       : DD.Config Msg
  , custom   : String
  , customSt : Api.State
  }

init : GLE.Recv -> Model
init f =
  { uid      = f.uid
  , vid      = f.vid
  , labels   = List.filter (\l -> l.id > 0) f.labels
  , sel      = Set.fromList f.selected
  , tsel     = Set.fromList f.selected
  , state    = Dict.empty
  , dd       = DD.init ("ulist_labeledit_dd" ++ f.vid) Open
  , custom   = ""
  , customSt = Api.Normal
  }

type Msg
  = Open Bool
  | Toggle Int Bool Bool
  | Custom String
  | CustomSubmit
  | CustomSaved GApi.Response
  | Saved Int Bool GApi.Response


isPublic : Model -> Bool
isPublic model = List.any (\lb -> lb.id /= 7 && not lb.private && Set.member lb.id model.sel) model.labels

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    Open b -> ({ model | dd = DD.toggle model.dd b }, Cmd.none)

    Toggle l cascade b ->
      ( { model
        | tsel   = if b then Set.insert l model.tsel else Set.remove l model.tsel
        , state  = Dict.insert l Api.Loading model.state
        }
      , Cmd.batch <|
           GLE.send { uid = model.uid, vid = model.vid, label = l, applied = b } (Saved l b)
           -- Unselect other progress labels (1..4) when setting a progress label
        :: if cascade
           then (List.map (\i -> selfCmd (Toggle i False False)) <| List.filter (\i -> l >= 1 && l <= 4 && i >= 1 && i <= 4 && i /= l) <| Set.toList model.tsel)
           else []
      )

    Custom t -> ({ model | custom = t }, Cmd.none)
    CustomSubmit -> ({ model | customSt = Api.Loading }, GLA.send { uid = model.uid, vid = model.vid, label = model.custom } CustomSaved)
    CustomSaved (GApi.LabelId id) ->
      let new = List.filter (\l -> l.id == id) model.labels |> List.isEmpty
      in ({ model | labels = if new then model.labels ++ [{ id = id, label = model.custom, private = True }] else model.labels
                  , customSt = Api.Normal, custom = ""
                  , sel = Set.insert id model.sel
                  , tsel = Set.insert id model.tsel
                  }, Cmd.none)
    CustomSaved e -> ({ model | customSt = Api.Error e }, Cmd.none)

    Saved l b (GApi.Success) ->
      let nmodel = { model | sel = if b then Set.insert l model.sel else Set.remove l model.sel, state = Dict.remove l model.state }
       in (nmodel, ulistLabelChanged (isPublic nmodel))
    Saved l b e -> ({ model | state = Dict.insert l (Api.Error e) model.state }, Cmd.none)


view : Model -> String -> Html Msg
view model txt =
  let
    lbl = List.intersperse (text ", ") <| List.filterMap (\l ->
      if l.id /= 7 && Set.member l.id model.sel
      then Just <| span []
            [ if l.id <= 6 && txt /= "-" then ulistIcon l.id l.label else text ""
            , text (" " ++ l.label) ]
      else Nothing) model.labels

    item l =
      li [ ]
      [ linkRadio (Set.member l.id model.tsel) (Toggle l.id True)
        [ text l.label
        , text " "
        , case Dict.get l.id model.state of
            Just Api.Loading -> span [ class "spinner" ] []
            Just (Api.Error _) -> b [] [ text "error" ] -- Need something better
            _ -> if l.id <= 6 then ulistIcon l.id l.label else text ""
        ]
      ]

    custom =
      li [] [
        case model.customSt of
          Api.Normal -> Html.form [ onSubmit CustomSubmit ]
                        [ inputText "" model.custom Custom ([placeholder "new label", style "width" "150px"] ++ GLA.valLabel) ]
          Api.Loading -> span [ class "spinner" ] []
          Api.Error _ -> b [] [ text "error" ] ]
  in
    DD.view model.dd
      (if List.any (\s -> s == Api.Loading) <| Dict.values model.state then Api.Loading else Api.Normal)
      (if List.isEmpty lbl then text txt else span [] lbl)
      (\_ -> [ ul [] <| List.map item (List.filter (\l -> l.id /= 7) model.labels) ++ [ custom ] ])
