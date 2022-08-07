# Radio
Listen to music in Co-op.

Any URL with video/audio present should work, unless you need to sign-in to view it. YouTube, SoundCloud, forum posts, Discord attachments are some examples. Basically, whatever [YouTube-DL](https://github.com/ytdl-org/youtube-dl/tree/master/youtube_dl/extractor) supports should work.

Benefits over traditional mic spamming:
- Volume is automatically normalized. No more "can you hear me?" troubleshooting.
- DJs can easily queue song requests from listeners and create a playlist.
- Audio can be muted without using the buggy scoreboard mute system.
- You know who is actually listening.
- No need to mute your game audio if you want to stream music.
- No interruption in music because the streamer has trouble holding their mic key down.
- Unlike normal mic audio, the radio does not slowly begin to stutter over time.

I recommend installing the [MicFix plugin](https://github.com/wootguy/MicFix) along with this.


## How does it look in the game?
Use .radio in the console, select a channel, become DJ and say ~yourYoutubeUrl to start the music. Everyone on the channel will listen to your track.

![](images-for-readme/how-it-looks.png)

There is an option for the Text-To-Speech function for chat messages. Check also .radio help.

## How does it work?
![](images-for-readme/how-it-works.png)

1. Player says which song to play
2. Angel script plugin writes this msg in the log file
3. Server (radio_server.py) checks this log file in the loop
4. Server says to the client about this msg
5. Client gets song from youtube
6. Client (radio_client.py) streams video into ffmpeg
7. Client notifies steam_voice about stream
8. Steam_voice streams ffmpeg into packets in the necessary format for sven plugins
9. Steam_voice sends those packets to the client
10. Client resends them to the server
11. Server writes them into the file format
12. Angel script reads them
13. Angel script plays the music and everybody is dancing, yay

## How to set up?
Check [this](how-to-set-up.md).
