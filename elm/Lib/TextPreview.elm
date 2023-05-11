module Lib.TextPreview exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Lib.Html exposing (..)
import Lib.Ffi as Ffi
import Lib.Api as Api
import Gen.Api as GApi
import Gen.Markdown as GM
import Gen.BBCode as GB


type alias Model =
  { state    : Api.State
  , data     : String  -- contents of the textarea
  , preview  : String  -- Rendered HTML, "" if not in sync with data
  , display  : Bool    -- False = textarea is displayed, True = preview is displayed
  , endpoint : { content : String } -> (GApi.Response -> Msg) -> Cmd Msg
  , class    : String
  }


bbcode : String -> Model
bbcode data =
  { state    = Api.Normal
  , data     = data
  , preview  = ""
  , display  = False
  , endpoint = GB.send
  , class    = "preview bbcode"
  }


markdown : String -> Model
markdown data =
  { state    = Api.Normal
  , data     = data
  , preview  = ""
  , display  = False
  , endpoint = GM.send
  , class    = "preview docs"
  }


type Msg
  = Edit String
  | TextArea
  | Preview
  | HandlePreview GApi.Response


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    Edit s   -> ({ model | preview = "", data = s, display = False, state = Api.Normal }, Cmd.none)
    TextArea -> ({ model | display = False }, Cmd.none)

    Preview ->
      if model.preview /= ""
      then ( { model | display = True }, Cmd.none)
      else ( { model | display = True, state = Api.Loading }
           , model.endpoint { content = model.data } HandlePreview
           )

    HandlePreview (GApi.Content s) -> ({ model | state = Api.Normal, preview = s }, Cmd.none)
    HandlePreview r -> ({ model | state = Api.Error r }, Cmd.none)


view : String -> Model -> (Msg -> m) -> Int -> List (Attribute m) -> List (Html m) -> Html m
view name model cmdmap width attr header =
  let
    display = model.display && model.preview /= ""
  in
    div [ class "textpreview", style "width" (String.fromInt width ++ "px") ]
    [ div []
      [ div [] header
      , div [ classList [("invisible", model.data == "")] ]
        [ case model.state of
            Api.Loading -> span [ class "spinner" ] []
            Api.Error _ -> small [] [ text "Error loading preview. " ]
            Api.Normal  -> text ""
        , if display
          then a [ onClickN (cmdmap TextArea) ] [ text "Edit" ]
          else span [] [text "Edit"]
        , if display
          then span [] [text "Preview"]
          else a [ onClickN (cmdmap Preview) ] [ text "Preview" ]
        ]
      ]
    , inputTextArea name model.data (cmdmap << Edit) (class (if display then "hidden" else "") :: attr)
    , if not display then text ""
      else div [ class model.class, Ffi.innerHtml model.preview ] []
    ]
