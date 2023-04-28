module Discussions.Poll exposing (main)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Browser
import Lib.Html exposing (..)
import Lib.TextPreview as TP
import Lib.Api as Api
import Gen.Api as GApi
import Gen.DiscussionsPoll as GDP


main : Program GDP.Recv Model Msg
main = Browser.element
  { init   = \e -> (init e, Cmd.none)
  , view   = view
  , update = update
  , subscriptions = always Sub.none
  }


type alias Model =
  { state  : Api.State
  , data   : GDP.Recv
  , voted  : Bool
  }


init : GDP.Recv -> Model
init d =
  { state  = Api.Normal
             -- Remove own vote from the count, so we can dynamically adjust the counter
  , data   = { d | options = List.map (\o -> { o | votes = if o.my then o.votes - 1 else o.votes }) d.options }
  , voted  = List.any (\o -> o.my) d.options
  }

type Msg
  = Preview
  | Vote Int Bool
  | Submit
  | Submitted GApi.Response


toomany : Model -> Bool
toomany model = List.length (List.filter (\o -> o.my) model.data.options) > model.data.max_options

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    Preview ->
      let d = model.data
          nd = { d | preview = True }
      in ({ model | data = nd }, Cmd.none)

    Vote n b ->
      let d = model.data
          nd = { d | options = List.map (\o -> { o | my = if n == o.id then b else o.my && d.max_options > 1 }) d.options }
      in ({ model | data = nd }, Cmd.none)

    Submit ->
      if toomany model then (model, Cmd.none)
      else
      ( { model | state = Api.Loading }
      , GDP.send { tid = model.data.tid, options = List.filterMap (\o -> if o.my then Just o.id else Nothing) model.data.options } Submitted
      )

    Submitted (GApi.Success) ->
      let d = model.data
          v = List.any (\o -> o.my) model.data.options
          nd = { d | num_votes = model.data.num_votes +
            case (model.voted, v) of
              (True, False) -> -1
              (False, True) ->  1
              _ -> 0 }
      in ({ model | state = Api.Normal, voted = v, data = nd }, Cmd.none)
    Submitted r -> ({ model | state = Api.Error r }, Cmd.none)


view : Model -> Html Msg
view model =
  let
    cvotes = model.data.num_votes + (if not model.voted && List.any (\o -> o.my) model.data.options then 1 else 0)
    nvotes o = if o.my then o.votes + 1 else o.votes
    max = toFloat <| Maybe.withDefault 1 <| List.maximum <| List.map nvotes model.data.options

    opt o =
      tr [ classList [("odd", o.my)] ]
      [ td [ class "tc1" ]
        [ label []
          [ if not model.data.can_vote
            then text ""
            else if model.data.max_options == 1
            then inputRadio "vote" o.my (Vote o.id)
            else inputCheck "" o.my (Vote o.id)
          , span [ class "option", classList [("own", o.my)] ] [ text o.option ]
          ]
        ]
      , if model.data.preview || model.voted
        then td [ class "tc2" ]
             [ div [ class "graph", style "width" (String.fromFloat (toFloat (nvotes o) / max * 200) ++ "px") ] [ text " " ]
             , div [ class "number" ] [ text <| String.fromInt (nvotes o) ]
             ]
        else td [ class "tc2", colspan 2 ] []
      , if model.data.preview || model.voted
        then td [ class "tc3" ]
             [ let pc = toFloat (nvotes o) / toFloat cvotes * 100
               in text <| String.fromInt (truncate pc) ++ "%" ]
        else text ""
      ]
  in
  form_ "" Submit (model.state == Api.Loading)
  [ article []
    [ h1 [] [ text model.data.question ]
    , table [ class "votebooth" ]
      [ if model.data.can_vote && model.data.max_options > 1
        then thead [] [ tr [] [ td [ colspan 3 ] [ i [] [ text <| "You may choose up to " ++ String.fromInt model.data.max_options ++ " options" ] ] ] ]
        else text ""
      , tfoot [] [ tr []
        [ td [ class "tc1" ]
          [ if model.data.can_vote
            then submitButton "Vote" model.state True
            else b [] [ text "You must be logged in to be able to vote." ]
          , if toomany model
            then b [] [ text "Too many options selected." ]
            else text ""
          ]
        , td [ class "tc2" ]
          [ if model.data.num_votes == 0
            then i [] [ text "Nobody voted yet" ]
            else if model.data.preview || model.voted
            then text <| (String.fromInt model.data.num_votes) ++ (if model.data.num_votes == 1 then " vote total" else " votes total")
            else a [ href "#", onClickD Preview ] [ text "View results" ]
          ]
        ] ]
      , tbody [] <| List.map opt model.data.options
      ]
    ]
  ]
