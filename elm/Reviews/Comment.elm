module Reviews.Comment exposing (main)

import Html exposing (..)
import Html.Attributes exposing (..)
import Browser
import Browser.Navigation exposing (load)
import Lib.Html exposing (..)
import Lib.TextPreview as TP
import Lib.Api as Api
import Gen.Api as GApi
import Gen.ReviewsComment as GRC


main : Program GRC.Send Model Msg
main = Browser.element
  { init   = \e -> ((Api.Normal, e.id, TP.bbcode ""), Cmd.none)
  , view   = view
  , update = update
  , subscriptions = always Sub.none
  }

type alias Model = (Api.State, String, TP.Model)

type Msg
  = Content TP.Msg
  | Submit
  | Submitted GApi.Response


update : Msg -> Model -> (Model, Cmd Msg)
update msg (state,id,content) =
  case msg of
    Content m -> let (nm,nc) = TP.update m content in ((state,id,nm), Cmd.map Content nc)
    Submit -> ((Api.Loading,id,content), GRC.send { msg = content.data, id = id } Submitted)
    Submitted (GApi.Redirect s) -> ((state,id,content), load s)
    Submitted r -> ((Api.Error r,id,content), Cmd.none)


view : Model -> Html Msg
view (state,_,content) =
  form_ "" Submit (state == Api.Loading)
  [ div [ class "mainbox" ]
    [ fieldset [ class "submit" ]
      [ TP.view "msg" content Content 600 ([rows 4, cols 50] ++ GRC.valMsg)
        [ b [] [ text "Comment" ]
        , b [ class "standout" ] [ text " (English please!) " ]
        , a [ href "/d9#3" ] [ text "Formatting" ]
        ]
      , submitButton "Submit" state True
      ]
    ]
  ]
