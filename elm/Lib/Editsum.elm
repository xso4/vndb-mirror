-- This module provides an the 'Edit summary' box, including the entry state
-- option for moderators.

module Lib.Editsum exposing (Model, Msg, new, update, view)

import Html exposing (..)
import Html.Attributes exposing (..)
import Lib.Html exposing (..)
import Lib.TextPreview as TP


type alias Model =
  { authmod  : Bool
  , hasawait : Bool
  , locked   : Bool
  , hidden   : Bool
  , editsum  : TP.Model
  }


type Msg
  = State Bool Bool Bool
  | Editsum TP.Msg


new : Model
new =
  { authmod  = False
  , hasawait = False
  , locked   = False
  , hidden   = False
  , editsum  = TP.bbcode ""
  }


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    State hid lock _ -> ({ model | hidden = hid, locked = lock }, Cmd.none)
    Editsum m -> let (nm,nc) = TP.update m model.editsum in ({ model | editsum = nm }, Cmd.map Editsum nc)


view : Model -> Html Msg
view model =
  let
    lockhid =
      [ label [] [ inputRadio "entry_state" (not model.hidden && not model.locked) (State False False), text " Normal " ]
      , label [] [ inputRadio "entry_state" (not model.hidden &&     model.locked) (State False True ), text " Locked " ]
      , label [] [ inputRadio "entry_state" (    model.hidden &&     model.locked) (State True  True ), text " Deleted " ]
      , if not model.hasawait then text "" else
        label [] [ inputRadio "entry_state" (    model.hidden && not model.locked) (State True  False), text " Awaiting approval" ]
      , br [] []
      , if model.hidden && model.locked
        then span [] [ text "Note: edit summary of the last edit should indicate the reason for the deletion.", br [] [] ]
        else text ""
      ]
  in fieldset [] <|
    (if model.authmod then lockhid else [])
    ++
    [ TP.view "" model.editsum Editsum 600 [rows 4, cols 50, minlength 2, maxlength 5000, required True]
      [ b [class "title"] [ text "Edit summary", b [] [ text " (English please!)" ] ]
      , br [] []
      , text "Summarize the changes you have made, including links to source(s)."
      ]
    ]
