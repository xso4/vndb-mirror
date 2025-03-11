-- This is basically the same thing as UList.Widget, but with a slightly different UI.
-- Release options are not available in this mode, as VN pages have a separate
-- release listing anyway.
module UList.VNPage exposing (main)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Browser
import Task
import Date
import Lib.Html exposing (..)
import Lib.Util exposing (..)
import Lib.Api as Api
import Lib.DropDown as DD
import Gen.UListWidget as GUW
import Gen.UListVNNotes as GVN
import UList.LabelEdit as LE
import UList.VoteEdit as VE
import UList.DateEdit as DE
import UList.Widget as UW

main : Program GUW.Recv UW.Model UW.Msg
main = Browser.element
  { init = \f -> (UW.init f, Date.today |> Task.perform UW.Today)
  , subscriptions = \m -> Sub.batch
    [ Sub.map UW.Label (DD.sub m.labels.dd)
    , Sub.map UW.Vote  (DD.sub m.vote.dd) ]
  , view = view
  , update = UW.update
  }


view : UW.Model -> Html UW.Msg
view model =
  let notesBut =
        [ a [ href "#", onClickD UW.NotesToggle ] [ text "💬" ]
        , span [ class "spinner", classList [("hidden", model.notesState /= Api.Loading)] ] []
        , case model.notesState of
            Api.Error e -> b [] [ text <| Api.showResponse e ]
            _ -> text ""
        ]
  in
  div [ class "ulistvn elm_dd_input" ]
  [ span [] (UW.viewStatus model)
  , strong [] [ text "User options" ]
  , table [ style "margin" "4px 0 0 0", style "width" "100%" ] <|
    [ tr [ class "odd" ]
      [ td [ class "key" ] [ text "My labels" ]
      , td [ colspan (if model.canvote then 2 else 1) ] [ Html.map UW.Label (LE.view model.labels "- select label -") ]
      , if model.canvote then text "" else td [] notesBut
      ]
    , if model.canvote
      then tr [ class "nostripe compact" ]
           [ td [] [ text "My vote" ]
           , td [ style "width" "80px" ] [ Html.map UW.Vote (VE.view model.vote "- vote -") ]
           , td [] <| notesBut ++ [ UW.viewReviewLink model ]
           ]
      else text ""
    ] ++ if not model.notesVis then [] else
    [ tr [ class "nostripe compact" ]
      [ td [] [ text "Notes" ]
      , td [ colspan 2 ]
        [ textarea [ id "widget-notes", placeholder "Notes", rows 2, cols 30, onInput UW.Notes, onBlur (UW.NotesSave model.notesRev), maxlength 2000] [ text model.notes ] ]
      ]
    ] ++ if not model.onlist then [] else
    [ tr [] [ td [] [ text "Start date"  ], td [ colspan 2, class "date" ] [ Html.map UW.Started  (DE.view model.started ) ] ]
    , tr [] [ td [] [ text "Finish date" ], td [ colspan 2, class "date" ] [ Html.map UW.Finished (DE.view model.finished) ] ]
    ]
  ]
