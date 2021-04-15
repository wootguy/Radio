from mutagen.mp3 import MP3
import mutagen
import os

root_dir = '../../../../svencoop_addon/mp3/radio_twlz/'
songlist = open("songs.txt", "w")

for root, folders, files in os.walk(root_dir):
	for filename in files:
		path = os.path.join(root, filename).replace("\\", "/")
		
		if ('version_check' in path):
			continue
		
		plugin_path = path.replace(root_dir, "")
		tags = mutagen.File(path, easy=True)
		length = int(MP3(path).info.length*1000)
		
		title = tags['title'][0] if 'title' in tags else filename
		artist = tags['artist'][0] if 'artist' in tags else '???'
		
		print("%s|%s|%s|%s" % (plugin_path, artist, title, length))
		songlist.write("%s|%s|%s|%s\n" % (plugin_path, artist, title, length))

songlist.close()