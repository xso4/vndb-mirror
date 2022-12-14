module TableOpts exposing (main)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Browser
import Task
import Process
import Bitwise as B
import Lib.Api as Api
import Lib.Html exposing (..)
import Lib.Util exposing (..)
import Lib.Ffi as Ffi
import Lib.DropDown exposing (onClickOutside)
import Gen.Api as GApi
import Gen.TableOptsSave as GTO


main : Program GTO.Recv Model Msg
main = Browser.element
  { init   = \e -> (init e, Cmd.none)
  , view   = view
  , update = update
  , subscriptions = \m ->
      let xid = case m.open of
                 TNone    -> ""
                 TSave    -> "tableopts-save"
                 TResults -> "tableopts-results"
                 TCols    -> "tableopts-cols"
                 TSort    -> "tableopts-sort"
      in if xid == "" then Sub.none else onClickOutside xid (Open TNone)
  }

type TOpen = TNone | TSave | TResults | TCols | TSort

type alias Model =
  { opts    : GTO.Recv
  , state   : Api.State
  , saved   : Bool
  , open    : TOpen
  , view    : Int
  , results : Int
  , asc     : Bool
  , sort    : Int
  , cols    : Int
  }

init : GTO.Recv -> Model
init opts =
  { opts    = opts
  , state   = Api.Normal
  , saved   = False
  , open    = TNone
  , view    = B.and 3 opts.value
  , results = B.and 7 (B.shiftRightBy 2 opts.value)
  , asc     = B.and 32 opts.value == 0
  , sort    = B.and 63 (B.shiftRightBy 6 opts.value)
  , cols    = B.shiftRightBy 12 opts.value
  }


type Msg
  = Noop
  | Open TOpen
  | View Int
  | Results Int
  | Sort Int Bool
  | Cols Int Bool
  | Save
  | Saved GApi.Response

doSubmit = Task.attempt (always Noop) <| Task.andThen (\_ -> Ffi.elemCall "click" "tableopts-submit") <| Process.sleep 1

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    Noop        -> (model, Cmd.none)
    Open o      -> ({ model | open = o }, Cmd.none)
    View n      -> ({ model | view = n }, doSubmit)
    Results n   -> ({ model | results = n }, doSubmit)
    Sort n b    -> ({ model | sort = n, asc = b }, doSubmit)
    Cols n b    -> ({ model | cols = if b then B.or model.cols (B.shiftLeftBy n 1) else B.and model.cols (B.xor (B.complement 0) (B.shiftLeftBy n 1)) }, Cmd.none)
    Save        -> ( { model | saved = False, state = Api.Loading }
                   , GTO.send { save = Maybe.withDefault "" model.opts.save
                              , value = if encInt model == model.opts.default then Nothing else Just (encInt model)
                              } Saved)
    Saved GApi.Success -> ({ model | saved = True, state = Api.Normal }, Cmd.none)
    Saved e -> ({ model | state = Api.Error e }, Cmd.none)


encBase64Alpha : Int -> String
encBase64Alpha n = String.slice n (n+1) "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_-"

encBase64 : Int -> String
encBase64 n = (if n >= 64 then encBase64 (n//64) else "") ++ encBase64Alpha (modBy 64 n)

encInt : Model -> Int
encInt m =
     B.xor m.view
  <| B.xor (B.shiftLeftBy 2 m.results)
  <| B.xor (if m.asc then 0 else 32)
  <| B.xor (B.shiftLeftBy 6 m.sort)
  <| B.shiftLeftBy 12 m.cols


-- SVG icons from Wordpress Dashicons, GPLv2.
-- Except for the floppy icon, that's from Fork Awesome, SIL OFL 1.1.
view : Model -> Html Msg
view model =
  let
    tabdd tobj label tit w f =
      div []
      [ a [ href "#", title tit
          , onClickD (Open (if model.open == tobj then TNone else tobj))
          , classList [("highlightselected", model.open == tobj)]
          , Ffi.innerHtml label
          ] []
      , if model.open /= tobj then text "" else
        div []
        [ div [ style "width" (String.fromInt w ++ "px"), style "left" (String.fromInt (-w+40) ++ "px") ]
          (h4 [] [ text tit ] :: f) ]
      ]

    save = tabdd TSave
      "<svg height=13 width=13 viewbox=\"0 0 1700 1700\"><path d=\"M384 1536h768v-384H384v384zm896 0h128V640c0-19-17-60-30-73l-281-281c-14-14-53-30-73-30v416c0 53-43 96-96 96H352c-53 0-96-43-96-96V256H128v1280h128v-416c0-53 43-96 96-96h832c53 0 96 43 96 96v416zM896 608V288c0-17-15-32-32-32H672c-17 0-32 15-32 32v320c0 17 15 32 32 32h192c17 0 32-15 32-32zm640 32v928c0 53-43 96-96 96H96c-53 0-96-43-96-96V224c0-53 43-96 96-96h928c53 0 126 30 164 68l280 280c38 38 68 111 68 164z\"/></svg>"
      "save display settings" 240
      [ case (model.state, model.saved) of
          (_, True)        -> text "Saved!"
          (Api.Loading, _) -> span [ class "spinner" ] []
          (Api.Error e, _) -> b [ class "standout" ] [ text <| Api.showResponse e ]
          _                -> inputButton "Save current settings as default" Save []
      ]

    resultLabel num =
      case num of
        1 -> "10"
        2 -> "25"
        3 -> "100"
        4 -> "200"
        _ -> "50"
    resultOpt num =
      if model.results == num
      then span [] [ text <| resultLabel num ]
      else a [ href "#", onClickD (Results num) ] [ text <| resultLabel num ]
    results = tabdd TResults (resultLabel model.results) "results per page" 180
      [ resultOpt 1, text " | "
      , resultOpt 2, text " | "
      , resultOpt 0, text " | "
      , resultOpt 3, text " | "
      , resultOpt 4
      ]

    cols = tabdd TCols
      "<svg height=13 width=13 viewbox=\"0 0 20 20\"><path d=\"M10 5.09c3.98 0 7.4 2.25 9 5.5-1.6 3.25-5.02 5.5-9 5.5s-7.4-2.25-9-5.5c1.6-3.25 5.02-5.5 9-5.5zm2.35 3.1c0-.59-.39-1.08-.92-1.24-.16-.02-.32-.03-.49-.04-.65.05-1.17.6-1.17 1.28 0 .71.58 1.29 1.29 1.29.72 0 1.29-.58 1.29-1.29zM10 14.89c3.36 0 6.25-1.88 7.6-4.3-.93-1.67-2.6-2.81-4.65-3.35a4.042 4.042 0 0 1-2.95 6.8 4.042 4.042 0 0 1-2.95-6.8C5 7.78 3.33 8.92 2.4 10.59c1.35 2.42 4.24 4.3 7.6 4.3z\"/></svg>"
      "visible columns" 150
      <| List.intersperse (br [] []) (List.map (\o ->
           linkRadio (B.and model.cols (B.shiftLeftBy o.id 1) > 0) (Cols o.id) [ text o.name ]
         ) model.opts.vis)
      ++ [ br [] [], input [ type_ "submit", class "submit", value "Update" ] [] ]

    sorts = tabdd TSort
      "<svg height=13 width=13 viewbox=\"0 0 20 20\"><path d=\"M11 7H1l5 7zm-2 7h10l-5-7z\"/></svg>"
      "sort options" 250
      [ table [ style "margin" "0 0 0 auto" ] <| List.map (\o ->
          let but w = a [ href "#", onClickD (Sort o.id w), classList [("checked", model.sort == o.id && model.asc == w)] ]
                      [ text <| case (o.num, w) of
                                  (True, True) -> "1→9"
                                  (True, False) -> "9→1"
                                  (False, True) -> "A→Z"
                                  (False, False) -> "Z→A" ]
          in tr []
             [ td [ style "padding" "0"      ] [ text o.name ]
             , td [ style "padding" "0 15px" ] [ but True  ]
             , td [ style "padding" "0"      ] [ but False ]
             ]
          ) model.opts.sorts ]

    viewIcon num label path =
      if List.filter (\x -> x == num) model.opts.views |> List.isEmpty
      then text ""
      else li [ style "margin-left" (if num == 0 then "10px" else "5px") ]
           [ a [ href "#", title label, onClickD (View num)
               , classList [("highlightselected", model.view == num)]
               , Ffi.innerHtml ("<svg height=13 width=13 viewbox=\"0 0 20 20\"><path d=\"" ++ path ++ "\"/></svg>") ] [] ]
  in
  ul [ id "tableopts" ]
    -- TODO: Only show save icon if different from currently saved settings?
  [ if not model.saved && model.opts.save == Nothing then text "" else
    li [ id "tableopts-save", class "maindd" ] [ save ]
  , li [ id "tableopts-results", class "maindd" ]
    -- The 'results' button is always visible, so we can hide our form elements in there
    [ if model.opts.save == Nothing && encInt model == model.opts.default
      then text ""
      else input [ type_ "hidden", name "s", value (encBase64 (encInt model)) ] []
    , input [ type_ "submit", id "tableopts-submit", class "hidden" ] []
    , results
    ]
  , if List.isEmpty model.opts.vis then text "" else
    li [ id "tableopts-cols", class "maindd"] [ cols ]
  , if List.isEmpty model.opts.sorts then text "" else
    li [ id "tableopts-sort", class "maindd" ] [ sorts ]
  , viewIcon 0 "List view" "M2 19h16c.55 0 1-.45 1-1V2c0-.55-.45-1-1-1H2c-.55 0-1 .45-1 1v16c0 .55.45 1 1 1zM4 3c.55 0 1 .45 1 1s-.45 1-1 1-1-.45-1-1 .45-1 1-1zm13 0v2H6V3h11zM4 7c.55 0 1 .45 1 1s-.45 1-1 1-1-.45-1-1 .45-1 1-1zm13 0v2H6V7h11zM4 11c.55 0 1 .45 1 1s-.45 1-1 1-1-.45-1-1 .45-1 1-1zm13 0v2H6v-2h11zM4 15c.55 0 1 .45 1 1s-.45 1-1 1-1-.45-1-1 .45-1 1-1zm13 0v2H6v-2h11z"
  , viewIcon 1 "Card view" "M19 18V2c0-.55-.45-1-1-1H2c-.55 0-1 .45-1 1v16c0 .55.45 1 1 1h16c.55 0 1-.45 1-1zM4 3c.55 0 1 .45 1 1s-.45 1-1 1-1-.45-1-1 .45-1 1-1zm13 0v6H6V3h11zM4 11c.55 0 1 .45 1 1s-.45 1-1 1-1-.45-1-1 .45-1 1-1zm13 0v6H6v-6h11z"
  , viewIcon 2 "Grid view" "M2 1h16c.55 0 1 .45 1 1v16c0 .55-.45 1-1 1H2c-.55 0-1-.45-1-1V2c0-.55.45-1 1-1zm7.01 7.99v-6H3v6h6.01zm8 0v-6h-6v6h6zm-8 8.01v-6H3v6h6.01zm8 0v-6h-6v6h6z"
  ]
