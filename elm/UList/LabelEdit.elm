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
  }

init : GLE.Recv -> Model
init f =
  { uid      = f.uid
  , vid      = f.vid
  , labels   = f.labels
  , sel      = Set.fromList f.selected
  , tsel     = Set.fromList f.selected
  , state    = Dict.empty
  , dd       = DD.init ("ulist_labeledit_dd" ++ f.vid) Open
  }

type Msg
  = Open Bool
  | Toggle Int Bool Bool
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
           then (List.map (\i -> selfCmd (Toggle i False False)) <| List.filter (\i -> l >= 0 && l <= 4 && i >= 0 && i <= 4 && i /= l) <| Set.toList model.tsel)
           else []
      )

    Saved l b (GApi.Success) ->
      let nmodel = { model | sel = if b then Set.insert l model.sel else Set.remove l model.sel, state = Dict.remove l model.state }
       in (nmodel, ulistLabelChanged (isPublic nmodel))
    Saved l b e -> ({ model | state = Dict.insert l (Api.Error e) model.state }, Cmd.none)


view : Model -> String -> Html Msg
view model txt =
  let
    str = String.join ", " <| List.filterMap (\l -> if l.id /= 7 && Set.member l.id model.sel then Just l.label else Nothing) model.labels

    item l =
      li [ ]
      [ linkRadio (Set.member l.id model.tsel) (Toggle l.id True)
        [ text l.label
        , text " "
        , span [ class "spinner", classList [("invisible", Dict.get l.id model.state /= Just Api.Loading)] ] []
        , case Dict.get l.id model.state of
            Just (Api.Error _) -> b [ class "standout" ] [ text "error" ] -- Need something better
            _ -> text ""
        ]
      ]
  in
    DD.view model.dd
      (if List.any (\s -> s == Api.Loading) <| Dict.values model.state then Api.Loading else Api.Normal)
      (text <| if str == "" then txt else str)
      (\_ -> [ ul [] <| List.map item <| List.filter (\l -> l.id /= 7) model.labels ])
