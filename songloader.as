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
