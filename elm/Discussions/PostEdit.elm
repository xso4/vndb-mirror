module Discussions.PostEdit exposing (main)

import Html exposing (..)
import Html.Attributes exposing (..)
import Browser
import Browser.Navigation exposing (load)
import Lib.Html exposing (..)
import Lib.TextPreview as TP
import Lib.Api as Api
import Gen.Api as GApi
import Gen.DiscussionsPostEdit as GPE


main : Program GPE.Recv Model Msg
main = Browser.element
  { init   = \e -> (init e, Cmd.none)
  , view   = view
  , update = update
  , subscriptions = always Sub.none
  }


type alias Model =
  { state       : Api.State
  , id          : String
  , num         : Int
  , can_mod     : Bool
  , hidden      : Bool
  , nolastmod   : Bool
  , delete      : Bool
  , msg         : TP.Model
  }


init : GPE.Recv -> Model
init d =
  { state       = Api.Normal
  , id          = d.id
  , num         = d.num
  , can_mod     = d.can_mod
  , hidden      = d.hidden
  , nolastmod   = False
  , delete      = False
  , msg         = TP.bbcode d.msg
  }

encode : Model -> GPE.Send
encode m =
  { id        = m.id
  , num       = m.num
  , hidden    = m.hidden
  , nolastmod = m.nolastmod
  , delete    = m.delete
  , msg       = m.msg.data
  }


type Msg
  = Hidden Bool
  | Nolastmod Bool
  | Delete Bool
  | Content TP.Msg
  | Submit
  | Submitted GApi.Response


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    Hidden  b     -> ({ model | hidden  = b }, Cmd.none)
    Nolastmod b   -> ({ model | nolastmod=b }, Cmd.none)
    Delete  b     -> ({ model | delete  = b }, Cmd.none)
    Content m     -> let (nm,nc) = TP.update m model.msg in ({ model | msg = nm }, Cmd.map Content nc)

    Submit -> ({ model | state = Api.Loading }, GPE.send (encode model) Submitted)
    Submitted (GApi.Redirect s) -> (model, load s)
    Submitted r -> ({ model | state = Api.Error r }, Cmd.none)


view : Model -> Html Msg
view model =
  form_ "" Submit (model.state == Api.Loading)
  [ div [ class "mainbox" ]
    [ h1 [] [ text "Edit post" ]
    , table [ class "formtable" ] <|
      [ formField "Post" [ a [ href <| "/" ++ model.id ++ "." ++ String.fromInt model.num ] [ text <| "#" ++ String.fromInt model.num ++ " on " ++ model.id ] ]
      , if model.can_mod
        then formField "" [ label [] [ inputCheck "" model.hidden Hidden, text " Hidden" ] ]
        else text ""
      , if model.can_mod
        then formField "" [ label [] [ inputCheck "" model.nolastmod Nolastmod, text " Don't update last modification timestamp" ] ]
        else text ""
      , tr [ class "newpart" ] [ td [ colspan 2 ] [ text "" ] ]
      , formField "msg::Message"
        [ TP.view "msg" model.msg Content 700 ([rows 12, cols 50] ++ GPE.valMsg)
          [ b [ class "standout" ] [ text " (English please!) " ]
          , a [ href "/d9#4" ] [ text "Formatting" ]
          ]
        ]
      ]
      ++ (if not model.can_mod then [] else
      [ tr [ class "newpart" ] [ td [ colspan 2 ] [ text "DANGER ZONE" ] ]
      , formField "" [ inputCheck "" model.delete Delete, text " Permanently delete this post. This action can not be reverted, only do this with obvious spam!" ]
      ])
    ]
  , div [ class "mainbox" ]
    [ fieldset [ class "submit" ] [ submitButton "Submit" model.state True ] ]
  ]
