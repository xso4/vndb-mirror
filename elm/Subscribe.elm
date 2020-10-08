module Subscribe exposing (main)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Browser
import Lib.Html exposing (..)
import Lib.Api as Api
import Lib.DropDown exposing (onClickOutside)
import Gen.Api as GApi
import Gen.Subscribe as GS


main : Program GS.Send Model Msg
main = Browser.element
  { init   = \e -> ({ state = Api.Normal, opened = False, data = e}, Cmd.none)
  , view   = view
  , update = update
  , subscriptions = \m -> if m.opened then onClickOutside "subscribe" (Opened False) else Sub.none
  }

type alias Model =
  { state  : Api.State
  , opened : Bool
  , data   : GS.Send
  }

type Msg
  = Opened Bool
  | SubNum Bool Bool
  | SubReview Bool
  | Submitted GApi.Response


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  let dat = model.data
      save nd = ({ model | data = nd, state = Api.Loading }, GS.send nd Submitted)
  in
  case msg of
    Opened b    -> ({ model | opened = b }, Cmd.none)
    SubNum v b  -> save { dat | subnum = if b then Just v else Nothing }
    SubReview b -> save { dat | subreview = b }
    Submitted e -> ({ model | state = if e == GApi.Success then Api.Normal else Api.Error e }, Cmd.none)


view : Model -> Html Msg
view model =
  let
    dat = model.data
    t = String.left 1 dat.id
    msg txt = p [] [ text txt, text " These can be disabled globally in your ", a [ href "/u/notifies" ] [ text "notification settings" ], text "." ]
  in
  div []
  [ a [ href "#", onClickD (Opened (not model.opened)), class (if (dat.noti > 0 && dat.subnum /= Just False) || dat.subnum == Just True || dat.subreview then "active" else "inactive") ] [ text "🔔" ]
  , if not model.opened then text ""
    else div [] [ div []
    [ h4 []
      [ if model.state == Api.Loading then span [ class "spinner", style "float" "right" ] [] else text ""
      , text "Manage Notifications"
      ]
    , case (t, dat.noti) of
        ("t", 1) -> msg "You receive notifications for replies because you have posted in this thread."
        ("t", 2) -> msg "You receive notifications for replies because this thread is linked to your personal board."
        ("t", 3) -> msg "You receive notifications for replies because you have posted in this thread and it is linked to your personal board."
        ("w", 1) -> msg "You receive notifications for new comments because you have commented on this review."
        ("w", 2) -> msg "You receive notifications for new comments because this is your review."
        ("w", 3) -> msg "You receive notifications for new comments because this is your review and you have commented it."
        (_,   1) -> msg "You receive edit notifications for this entry because you have contributed to it."
        _ -> text ""
    , if dat.noti == 0 then text "" else
      label []
      [ inputCheck "" (dat.subnum == Just False) (SubNum False)
      , case t of
          "t" -> text " Disable notifications only for this thread."
          "w" -> text " Disable notifications only for this review."
          _   -> text " Disable edit notifications only for this entry."
      ]
    , label []
      [ inputCheck "" (dat.subnum == Just True) (SubNum True)
      , case t of
          "t" -> text " Enable notifications for new replies"
          "w" -> text " Enable notifications for new comments"
          _   -> text " Enable notifications for new edits"
      , if dat.noti == 0 then text "." else text ", regardless of the global setting."
      ]
    , if t /= "v" then text "" else
      label [] [ inputCheck "" dat.subreview SubReview, text " Enable notifications for new reviews." ]
    , case model.state of
        Api.Error e -> b [ class "standout" ] [ br [] [], text (Api.showResponse e) ]
        _ -> text ""
    ] ]
  ]
