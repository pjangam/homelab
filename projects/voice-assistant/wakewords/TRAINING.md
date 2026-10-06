# Training a custom wake word ("Alejandro")

openWakeWord models are trained on synthetic speech: Piper text-to-speech says
the phrase thousands of times in hundreds of voices, mixed with noise and room
echo, against hours of ordinary speech it must *not* wake on. No recordings of
your own voice are needed. Training runs on Google Colab (free GPU, in the
browser), never on xero.

Not in the community collection
(https://github.com/fwartner/home-assistant-wakewords-collection, checked
2026-10-06), so it has to be trained.

## On Colab (about an hour, mostly waiting)

1. Open the simple notebook linked from the openWakeWord README
   ("Training New Models", option 1):
   https://colab.research.google.com/drive/1q1oe2zOyZp7UsB3jJiQ1IFn8z5YfjwEb
   Sign in with a Google account. *Runtime -> Change runtime type -> T4 GPU*
   if it is not already on a GPU.
2. **Pronunciation first.** In the first section, set the target word to
   `alejandro` and run that cell. It generates a sample clip: play it.
   If it doesn't sound like you say it, respell it phonetically and rerun,
   e.g. `ah leh hahn dro` or `ah lay hahn dro`, until it does. Underscores or
   spaces between syllables are fine. Write down the spelling that worked.
3. **Train.** In the training section, keep the defaults for a first model
   (number of examples, training steps, false-activation penalty). Then
   *Runtime -> Run all* or run the remaining cells in order. Leave the tab
   open; if Colab disconnects, rerun from the top.
4. **Download.** The last cell downloads the model. Keep the `.tflite` file
   (the `.onnx` one is not needed). Rename it to `alejandro.tflite` if it is
   called something else - the file name becomes the wake word id.

If it later wakes too rarely: retrain with more examples / steps, or lower
the detection threshold on xero first (cheaper). If it wakes on random
speech or music (the Lady Gaga song exists): raise the false-activation
penalty and retrain.

## Back on xero (Claude can do this part)

1. Copy the file here: `projects/voice-assistant/wakewords/alejandro.tflite`
   (from the Mac: `scp alejandro.tflite pramod@xero:code/homelab/projects/voice-assistant/wakewords/`).
2. In `docker-compose.yml`, `openwakeword` gets `--preload-model=alejandro`
   (the folder is already mounted as `--custom-model-dir=/custom`), then
   `docker compose up -d openwakeword`.
3. Set `WAKE_WORD_ID = "alejandro"` in `../setup_assist.py`, run it, then
   `docker restart speech-to-phrase` (it must be restarted after every
   `setup_assist.py` run).
4. Test from the satellite and tune the threshold (`--threshold`, default 0.5)
   if needed. No ESP32 reflash: the board only streams audio; xero does the
   wake word.
