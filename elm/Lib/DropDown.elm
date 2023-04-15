module Lib.DropDown exposing (Config, init, sub, toggle, view, onClickOutside)

import Browser.Events as E
import Json.Decode as JD
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Lib.Api as Api
import Lib.Html exposing (..)


type alias Config msg =
  { id     : String
  , opened : Bool
  , hover  : Bool -- if true, the dropdown opens on mouse-over rather than click (not currently used)
  , toggle : Bool -> msg
  }


-- Returns True if the element or any of its parents has the given id
onClickOutsideParse : String -> JD.Decoder Bool
onClickOutsideParse id =
  JD.oneOf
  [ JD.field "id" JD.string |> JD.andThen (\s -> if id == s then JD.succeed True else JD.fail "")
  , JD.field "parentNode" <| JD.lazy <| \_ -> onClickOutsideParse id
  , JD.succeed False
  ]

-- onClick subscription that only fires when the click was outside of the element with the given id
onClickOutside : String -> msg -> Sub msg
onClickOutside id msg =
  E.onClick (JD.field "target" (onClickOutsideParse id) |> JD.andThen (\b -> if b then JD.fail "" else JD.succeed msg))


init : String -> (Bool -> msg) -> Config msg
init id msg =
  { id     = id
  , opened = False
  , hover  = False
  , toggle = msg
  }


sub : Config msg -> Sub msg
sub conf = if conf.opened && not conf.hover then onClickOutside conf.id (conf.toggle False) else Sub.none


toggle : Config msg -> Bool -> Config msg
toggle conf opened = { conf | opened = opened }


view : Config msg -> Api.State -> Html msg -> (() -> List (Html msg)) -> Html msg
view conf status lbl cont =
  div
  ( [ class "elm_dd", id conf.id
    ] ++ if conf.hover then [ onMouseLeave (conf.toggle False) ] else []
  )
  [ a
    ( [ href "#", onClickD (conf.toggle (if conf.hover then conf.opened else not conf.opened))
      ] ++ if conf.hover then [ onMouseEnter (conf.toggle True) ] else []
    ) <|
    case status of
      Api.Normal  -> [ lbl, span [] [ span [ class "arrow" ] [ text "▾" ] ] ]
      Api.Loading -> [ lbl, span [] [ span [ class "spinner" ] [] ] ]
      Api.Error e -> [ b [] [ text "error" ], span [] [ span [ class "arrow" ] [ text "▾" ] ] ]
  , div [ classList [("hidden", not conf.opened)] ]
    [ if conf.opened then div [] (cont ()) else text "" ]
  ]
