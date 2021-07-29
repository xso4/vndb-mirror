module VNLengthVote exposing (main)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Browser
import Lib.Html exposing (..)
import Lib.Api as Api
import Lib.RDate as RDate
import Gen.Api as GApi
import Gen.VNLengthVote as GV
import Gen.Release as GR


main : Program GV.Send Model Msg
main = Browser.element
  { init   = \e -> (init e, Cmd.none)
  , view   = view
  , update = update
  , subscriptions = always Sub.none
  }

type alias Model =
  { state   : Api.State
  , open    : Bool
  , uid     : String
  , vid     : String
  , rid     : String
  , defrid  : String
  , length  : Int
  , slength : Int
  , notes   : String
  , rels    : Maybe (List (String, String))
  }

init : GV.Send -> Model
init f =
  { state   = Api.Normal
  , open    = False
  , uid     = f.uid
  , vid     = f.vid
  , rid     = Maybe.map (\v -> v.rid)    f.vote |> Maybe.withDefault ""
  , defrid  = ""
  , length  = Maybe.map (\v -> v.length) f.vote |> Maybe.withDefault 0
  , slength = Maybe.map (\v -> v.length) f.vote |> Maybe.withDefault 0
  , notes   = Maybe.map (\v -> v.notes)  f.vote |> Maybe.withDefault ""
  , rels    = Nothing
  }

encode : Model -> GV.Send
encode m =
  { uid = m.uid
  , vid = m.vid
  , vote = if m.length == 0 then Nothing else Just { rid = m.rid, length = m.length, notes = m.notes }
  }

type Msg
  = Open Bool
  | Length (Maybe Int)
  | Release String
  | Notes String
  | RelLoaded GApi.Response
  | Delete
  | Submit
  | Submitted GApi.Response


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    Open b ->
      if b && model.rels == Nothing
      then ({ model | open = b, state = Api.Loading }, GR.send { vid = model.vid } RelLoaded)
      else ({ model | open = b }, Cmd.none)
    Length n  -> ({ model | length = 60 * Maybe.withDefault 0 n }, Cmd.none)
    Release s -> ({ model | rid = s }, Cmd.none)
    Notes s   -> ({ model | notes  = s }, Cmd.none)
    RelLoaded (GApi.Releases rels) ->
      let def = case rels of
                  [r] -> r.id
                  _ -> ""
      in ({ model | state = Api.Normal
          , rels = Just <| List.map (\r -> (r.id, RDate.showrel r)) rels
          , rid = if model.rid == "" then def else model.rid
         }, Cmd.none)
    RelLoaded e -> ({ model | state = Api.Error e }, Cmd.none)
    Delete      -> let m = { model | length = 0, rid = model.defrid, notes = "", state = Api.Loading } in (m, GV.send (encode m) Submitted)
    Submit      -> ({ model | state = Api.Loading }, GV.send (encode model) Submitted)
    Submitted (GApi.Success) -> ({ model | open = False, state = Api.Normal, slength = model.length }, Cmd.none)
    Submitted r -> ({ model | state = Api.Error r }, Cmd.none)


view : Model -> Html Msg
view model = span [] <|
  let
    frm = [ form_ "" (if model.rid == "" then Open True else Submit) False
      [ text "My play time: "
      , inputNumber "" (if model.length == 0 then Nothing else Just (model.length//60)) Length <|
        [ Html.Attributes.min "1", Html.Attributes.max "500", required True ]
      , text " hours"
      , br [] []
      , if model.defrid /= "" then text "" else
        inputSelect "" model.rid Release [style "width" "100%"] <|
          ("", "-- select release --") :: (Maybe.withDefault [] model.rels)
      , inputTextArea "" model.notes Notes
        [rows 2, cols 30, style "width" "100%", placeholder "(Optional) comments that may be helpful. For example, did you complete all routes, did you use auto mode? etc." ]
      , if model.slength == 0 then text "" else inputButton "Delete my vote" Delete [style "float" "right"]
      , if model.length == 0 || model.rid == "" then text "" else submitButton "Save" model.state True
      , inputButton "Cancel" (Open False) []
      ] ]
  in
    [ text " "
    , a [ onClickD (Open (not model.open)), href "#" ]
      [ text <| if model.slength == 0 then "Vote »"
        else "My vote: " ++ String.fromInt (model.slength // 60) ++ "h" ] -- TODO minute
    ] ++ case (model.open, model.state) of
          (False, _) -> []
          (_, Api.Normal) -> frm
          (_, Api.Error e) -> [ br [] [], b [ class "standout" ] [ text ("Error: " ++ Api.showResponse e) ] ]
          (_, Api.Loading) -> [ span [ class "spinner" ] [] ]
