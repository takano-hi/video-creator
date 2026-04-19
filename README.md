# Generate VOICEVOX subtitle

## usage

- create directory `$HOME/Movie/voicevox`
- create directory for video title
- output separated audio files (\*.wav) from voicevox into the directory
- output merged subtitle file from voicevox into the directory
  - name the file `subtitle.csv`
  - You can add `{br}` to break line in one statement
- put background image file as `cover.png` into the directory
- run the script: `TITLE=xxx ruby generate-video.rb`
