-- Utility module and UI widget for handling release dates.
--
-- Release dates are integers with the following format: 0, 1 or yyyymmdd
-- Special values
--          0 -> unknown
--          1 -> "today" (only used as filter)
--   99999999 -> TBA
--   yyyy9999 -> year known, month & day unknown
--   yyyymm99 -> year & month known, day unknown
module Lib.RDate exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Date
import Lib.Html exposing (..)
import Gen.Types as GT


type alias RDate = Int

type alias RDateComp =
  { y : Int
  , m : Int
  , d : Int
  }


expand : RDate -> RDateComp
expand r =
  { y = r // 10000
  , m = modBy 100 (r // 100)
  , d = modBy 100 r
  }


compact : RDateComp -> RDate
compact r = r.y * 10000 + r.m * 100 + r.d


fromDate : Date.Date -> RDateComp
fromDate d =
  { y = Date.year d
  , m = Date.monthNumber d
  , d = Date.day d
  }


normalize : RDateComp -> RDateComp
normalize r =
       if r.y == 0    then { y = 0,    m = 0,  d = clamp 0 1 r.y }
  else if r.y == 9999 then { y = 9999, m = 99, d = 99 }
  else if r.m == 0 || r.m == 99 then { y = r.y,  m = 99, d = 99 }
  else if r.d == 0 then { r | d = 99 }
  else r


format : RDateComp -> String
format date =
  case (date.y, date.m, date.d) of
    (   0,  0,  1) -> "today"
    (   0,  _,  _) -> "unknown"
    (9999,  _,  _) -> "TBA"
    (   y, 99, 99) -> String.fromInt y
    (   y,  m, 99) -> String.fromInt y ++ "-" ++ (String.padLeft 2 '0' <| String.fromInt m)
    (   y,  m,  d) -> String.fromInt y ++ "-" ++ (String.padLeft 2 '0' <| String.fromInt m) ++ "-" ++ (String.padLeft 2 '0' <| String.fromInt d)


display : Date.Date -> RDate -> Html msg
display today d =
  let fmt = expand d |> format
      future = d > (fromDate today |> compact)
  in if future then b [ class "future" ] [ text fmt ] else text fmt


-- Input widget.
--
-- BUG: Changing the month or year fields when day 30-31 is selected but no
-- longer valid results in an invalid RDate. It also causes the "-day-" option
-- to be selected (which is good), so I don't expect that many people will try
-- to submit the form without changing it.
view : RDate -> Bool -> Bool -> (RDate -> msg) -> Html msg
view ro permitUnknown permitToday msg =
  let r = expand ro
      range from to f = List.range from to |> List.map (\n -> (f n |> normalize |> compact, String.fromInt n))
      yl = (if permitToday   then [(1, "Today"  )] else [])
        ++ (if permitUnknown then [(0, "Unknown")] else [])
        ++ [(99999999, "TBA")]
        ++ List.reverse (range 1980 (GT.curYear + 5) (\n -> {r|y=n}))
      ml = ({r|m=99} |> normalize |> compact, "- month -") :: range 1 12 (\n -> {r|m=n})
      maxDay = Date.fromCalendarDate r.y (Date.numberToMonth r.m) 1 |> Date.add Date.Months 1 |> Date.add Date.Days -1 |> Date.day
      dl = ({r|d=99} |> normalize |> compact, "- day -") :: range 1 maxDay (\n -> {r|d=n})
  in div []
    [ inputSelect "" ro msg [ style "width" "100px" ] yl
    , if r.y == 0 || r.y == 9999 then text "" else inputSelect "" ro msg [ style "width" "90px" ] ml
    , if r.m == 0 || r.m ==   99 then text "" else inputSelect "" ro msg [ style "width" "90px" ] dl
    ]
