module VNLengthVote exposing (main)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Browser
import Browser.Dom exposing (focus)
import Task
import Date
import Lib.Html exposing (..)
import Lib.Api as Api
import Lib.RDate as RDate
import Gen.Api as GApi
import Gen.VNLengthVote as GV
import Gen.Release as GR


main : Program GV.Send Model Msg
main = Browser.element
  { init   = \e -> (init e, Date.today |> Task.perform Today)
  , view   = view
  , update = update
  , subscriptions = always Sub.none
  }

type alias Model =
  { state   : Api.State
  , open    : Bool
  , today   : Int
  , uid     : String
  , vid     : String
  , rid     : String
  , defrid  : String
  , hours   : Maybe Int
  , minutes : Maybe Int
  , speed   : Int
  , length  : Int -- last saved length
  , notes   : String
  , rels    : Maybe (List (String, String))
  }

init : GV.Send -> Model
init f =
  { state   = Api.Normal
  , today   = 0
  , open    = False
  , uid     = f.uid
  , vid     = f.vid
  , rid     = Maybe.map (\v -> v.rid) f.vote |> Maybe.withDefault ""
  , defrid  = ""
  , hours   = Maybe.map (\v -> v.length // 60   ) f.vote
  , minutes = Maybe.map (\v -> modBy 60 v.length) f.vote
  , speed   = Maybe.map (\v -> v.speed)  f.vote |> Maybe.withDefault -1
  , length  = Maybe.map (\v -> v.length) f.vote |> Maybe.withDefault 0
  , notes   = Maybe.map (\v -> v.notes)  f.vote |> Maybe.withDefault ""
  , rels    = Nothing
  }

enclen : Model -> Int
enclen m = (Maybe.withDefault 0 m.hours) * 60 + Maybe.withDefault 0 m.minutes

encode : Model -> GV.Send
encode m =
  { uid = m.uid
  , vid = m.vid
  , vote = if enclen m == 0 then Nothing else Just { rid = m.rid, notes = m.notes, speed = m.speed, length = enclen m }
  }

type Msg
  = Noop
  | Open Bool
  | Today Date.Date
  | Hours (Maybe Int)
  | Minutes (Maybe Int)
  | Speed Int
  | Release String
  | Notes String
  | RelLoaded GApi.Response
  | Delete
  | Submit
  | Submitted GApi.Response


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    Noop -> (model, Cmd.none)
    Open b ->
      if b && model.rels == Nothing
      then ({ model | open = b, state = Api.Loading }, GR.send { vid = model.vid } RelLoaded)
      else ({ model | open = b }, Cmd.none)
    Today d   -> ({ model | today = RDate.fromDate d |> RDate.compact }, Cmd.none)
    Hours n   -> ({ model | hours = n }, Cmd.none)
    Minutes n -> ({ model | minutes = n }, Cmd.none)
    Speed n   -> ({ model | speed = n }, Cmd.none)
    Release s -> ({ model | rid = s }, Cmd.none)
    Notes s   -> ({ model | notes  = s }, Cmd.none)
    RelLoaded (GApi.Releases rels) ->
      let rel r = if r.rtype /= "trial" && r.released <= model.today then Just (r.id, RDate.showrel r) else Nothing
          frels = List.filterMap rel rels
          def = case frels of
                  [(r,_)] -> r
                  _ -> ""
      in ({ model | state = Api.Normal
          , rels = Just frels
          , defrid = def
          , rid = if model.rid == "" then def else model.rid
         }, if model.hours == Nothing then Task.attempt (always Noop) (focus "vnlengthhours") else Cmd.none)
    RelLoaded e -> ({ model | state = Api.Error e }, Cmd.none)
    Delete      -> let m = { model | hours = Nothing, minutes = Nothing, rid = model.defrid, notes = "", state = Api.Loading } in (m, GV.send (encode m) Submitted)
    Submit      -> ({ model | state = Api.Loading }, GV.send (encode model) Submitted)
    Submitted (GApi.Success) ->
      ({ model | open = False, state = Api.Normal
       , length = (Maybe.withDefault 0 model.hours) * 60 + Maybe.withDefault 0 model.minutes
       }, Cmd.none)
    Submitted r -> ({ model | state = Api.Error r }, Cmd.none)


view : Model -> Html Msg
view model = div [class "lengthvotefrm"] <|
  let
    cansubmit = enclen model > 0 && model.speed /= -1 && model.rid /= ""
    rels = Maybe.withDefault [] model.rels
    frm = [ form_ "" (if cansubmit then Submit else Noop) False
      [ br_ 2
      , text "How long did you take to finish this VN?"
      , br [] []
      , text "- Only vote if you've completed all normal/true endings."
      , br [] []
      , text "- Exact measurements preferred, but rough estimates are accepted too."
      , br [] []
      , text "Play time: "
      , inputNumber "vnlengthhours" model.hours Hours [ Html.Attributes.min "0", Html.Attributes.max "500" ]
      , text " hours "
      , inputNumber "" model.minutes Minutes [ Html.Attributes.min "0", Html.Attributes.max "59" ]
      , text " minutes"
      , br [] []
      , if model.defrid /= "" then text "" else -- TODO: Handle missing model.rid
        inputSelect "" model.rid Release [style "width" "100%"]
        <| ("", "-- select release --") :: rels
        ++ if model.rid == "" || List.any (\(r,_) -> r == model.rid) rels then [] else [(model.rid, "[deleted/moved release: " ++ model.rid ++ "]")]
      , inputSelect "" model.speed Speed [style "width" "100%"]
        [ (-1, "-- how do you estimate your read/play speed? --")
        , (0, "Slow (e.g. low language proficiency or extra time spent on gameplay)")
        , (1, "Normal (no content skipped, all voices listened to end)")
        , (2, "Fast (e.g. fast reader or skipping through voices and gameplay)")
        ]
      , inputTextArea "" model.notes Notes
        [rows 2, cols 30, style "width" "100%", placeholder "(Optional) comments that may be helpful. For example, did you complete all the bad endings, how did you measure? etc." ]
      , if model.length == 0 then text "" else inputButton "Delete my vote" Delete [style "float" "right"]
      , if cansubmit then submitButton "Save" model.state True else text ""
      , inputButton "Cancel" (Open False) []
      , br_ 2
      ] ]
  in
    [ text " "
    , a [ onClickD (Open (not model.open)), href "#", style "float" "right" ]
      [ text <| if model.length == 0 then "Vote »"
        else "My vote: " ++ String.fromInt (model.length // 60) ++ "h"
                         ++ if modBy 60 model.length /= 0 then String.fromInt (modBy 60 model.length) ++ "m" else "" ]
    ] ++ case (model.open, model.state) of
          (False, _) -> []
          (_, Api.Normal) -> frm
          (_, Api.Error e) -> [ br_ 2, b [ class "standout" ] [ text ("Error: " ++ Api.showResponse e) ] ]
          (_, Api.Loading) -> [ span [ style "float" "right", class "spinner" ] [] ]
