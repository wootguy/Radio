void loadSongs() {
	g_songs.resize(0);
	g_root_folder.children.resize(0);
	
	File@ file = g_FileSystem.OpenFile(SONG_FILE_PATH, OpenFile::READ);

	if (file !is null && file.IsOpen()) {
		while (!file.EOFReached()) {
			string line;
			file.ReadLine(line);
			
			if (line.IsEmpty())
				continue;
			
			array<string> parts = line.Split("|");

			Song song;
			song.path = parts[0];
			song.artist = parts[1];
			song.title = parts[2];
			song.lengthMillis = atoi(parts[3]);
			
			song.searchName = song.getName().ToLowercase();
			
			g_songs.insertLast(song);
			
			string fname = song.path;
			string parentDir = "";
			if (int(song.path.Find("/")) != -1) {
				parentDir = fname.SubString(0, fname.FindLastOf("/"));
				fname = fname.SubString(fname.FindLastOf("/")+1);
			}
			addFileNode(parentDir, fname, song);
		}

		file.Close();
	} else {
		g_Log.PrintF("[Radio] song list file not found: " + SONG_FILE_PATH + "\n");
	}
}

enum MusicPackParseModes {
	PARSE_INFO,
	PARSE_PACK_DESC,
	PARSE_PACK_LINK,
}

void loadMusicPackInfo() {
	g_music_packs.resize(0);
	g_music_pack_update_time = "???";
	g_version_check_file = "???";
	
	File@ file = g_FileSystem.OpenFile(MUSIC_PACK_PATH, OpenFile::READ);

	MusicPack pack;
	int parse_mode = -1;

	if (file !is null && file.IsOpen()) {
		while (!file.EOFReached()) {
			string line;
			file.ReadLine(line);
			
			line.Trim();
			
			if (line.IsEmpty())
				continue;
			
			if (line == "[info]") {
				parse_mode = PARSE_INFO;
				continue;
			} else if (line == "[music_pack]") {
				parse_mode = PARSE_PACK_DESC;
				continue;
			}
			
			if (parse_mode == PARSE_INFO) {			
				array<string> parts = line.Split("=");
				string key = parts[0];
				string value = parts[1];
				key.Trim();
				value.Trim();
				
				if (key == "last_update_time") {
					g_music_pack_update_time = value;
				} else if (key == "version_check_file") {
					g_version_check_file = value;
					g_version_check_spr = g_version_check_file;
					g_version_check_spr = g_version_check_spr.Replace(".mp3", ".spr");
				} else if (key == "root_path") {
					g_root_path = value;
				}
			}
			else if (parse_mode == PARSE_PACK_DESC) {
				pack.desc = line;
				parse_mode = PARSE_PACK_LINK;
			}
			else if (parse_mode == PARSE_PACK_LINK) {
				pack.link = line;
				g_music_packs.insertLast(pack);
				parse_mode = -1;
				println("Added music pack:\n" + pack.desc + "\n" + pack.link);
			}
		}

		file.Close();
	} else {
		g_Log.PrintF("[Radio] music pack file not found: " + MUSIC_PACK_PATH + "\n");
	}
}

void addFileNode(string parentNodePath, string nodeName, Song@ song=null) {
	FileNode@ currentNode = g_root_folder;
	
	while (parentNodePath.Length() > 0) {
		int islash = int(parentNodePath.Find("/"));
		
		string nextDir = parentNodePath;
		
		if (islash != -1) {
			nextDir = parentNodePath.SubString(0, islash);
			parentNodePath = parentNodePath.SubString(islash+1);
		} else {
			parentNodePath = "";
		}
			
		bool found = false;
		for (uint i = 0; i < currentNode.children.size(); i++) {
			if (currentNode.children[i].name == nextDir) {
				@currentNode = @currentNode.children[i];
				found = true;
				break;
			}
		}
		
		if (!found) {
			FileNode newNode;
			newNode.name = nextDir;
			currentNode.children.insertLast(newNode);
			
			@currentNode = @newNode;
		}
	}
	
	FileNode newNode;
	newNode.name = nodeName;
	@newNode.file = @song;
	
	currentNode.children.insertLast(newNode);
}

FileNode@ getNodeFromPath(string path) {
	FileNode@ currentNode = g_root_folder;
	
	while (path.Length() > 0) {
		int islash = int(path.Find("/"));
		
		string nextDir = path;
		
		if (islash != -1) {
			nextDir = path.SubString(0, islash);
			path = path.SubString(islash+1);
		} else {
			path = "";
		}
			
		bool found = false;
		for (uint i = 0; i < currentNode.children.size(); i++) {
			if (currentNode.children[i].name == nextDir) {
				@currentNode = @currentNode.children[i];
				found = true;
				break;
			}
		}
		
		if (!found) {
			println("Node " + currentNode.name + " has no child " + nextDir);
			return null;
		}
	}
	
	return currentNode;
}
