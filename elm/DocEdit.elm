module DocEdit exposing (main)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Browser
import Browser.Navigation exposing (load)
import Lib.Html exposing (..)
import Lib.TextPreview as TP
import Lib.Api as Api
import Lib.Ffi as Ffi
import Lib.Editsum as Editsum
import Gen.Api as GApi
import Gen.DocEdit as GD


main : Program GD.Recv Model Msg
main = Browser.element
  { init   = \e -> (init e, Cmd.none)
  , view   = view
  , update = update
  , subscriptions = always Sub.none
  }


type alias Model =
  { state       : Api.State
  , editsum     : Editsum.Model
  , title       : String
  , content     : TP.Model
  , id          : String
  }


init : GD.Recv -> Model
init d =
  { state       = Api.Normal
  , editsum     = { authmod = True, editsum = TP.bbcode d.editsum, locked = d.locked, hidden = d.hidden }
  , title       = d.title
  , content     = TP.markdown d.content
  , id          = d.id
  }


encode : Model -> GD.Send
encode model =
  { id          = model.id
  , editsum     = model.editsum.editsum.data
  , hidden      = model.editsum.hidden
  , locked      = model.editsum.locked
  , title       = model.title
  , content     = model.content.data
  }


type Msg
  = Editsum Editsum.Msg
  | Submit
  | Submitted GApi.Response
  | Title String
  | Content TP.Msg


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    Editsum m  -> let (nm,nc) = Editsum.update m model.editsum in ({ model | editsum = nm }, Cmd.map Editsum nc)
    Title s   -> ({ model | title   = s }, Cmd.none)
    Content m -> let (nm,nc) = TP.update m model.content in ({ model | content = nm }, Cmd.map Content nc)

    Submit -> ({ model | state = Api.Loading }, GD.send (encode model) Submitted)
    Submitted (GApi.Redirect s) -> (model, load s)
    Submitted r -> ({ model | state = Api.Error r }, Cmd.none)


view : Model -> Html Msg
view model =
  form_ "" Submit (model.state == Api.Loading)
    [ div [ class "mainbox" ]
      [ h1 [] [ text <| "Edit " ++ model.id ]
      , table [ class "formtable" ]
        [ formField "title::Title" [ inputText "title" model.title Title (style "width" "300px" :: GD.valTitle) ]
        , formField "none"
          [ br_ 1
          , b [] [ text "Contents" ]
          , TP.view "content" model.content Content 850 ([rows 50, cols 90] ++ GD.valContent)
            [ text "HTML and MultiMarkdown supported, which is "
            , a [ href "https://daringfireball.net/projects/markdown/basics", target "_blank" ] [ text "Markdown" ]
            , text " with some "
            , a [ href "http://fletcher.github.io/MultiMarkdown-5/syntax.html", target "_blank" ][ text "extensions" ]
            , text "."
            ]
          ]
        ]
      ]
    , div [ class "mainbox" ]
      [ fieldset [ class "submit" ]
        [ Html.map Editsum (Editsum.view model.editsum)
        , submitButton "Submit" model.state True
        ]
      ]
    ]
