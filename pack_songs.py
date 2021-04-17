import os, sys, datetime, shutil
from threading import Thread

parallel_thread_count = 8
src_dir = '../../../../svencoop_addon/mp3/radio_twlz_high/'
readme = 'radio_twlz_readme.txt'
version_file_src = 'version_check_success.mp3'
version_file_dst = 'version_check/v2.mp3'

target_level = -1 # -1 = convert to all quality levels

quality_levels = [
	'-qscale:a 5 -ar 44100',
	'-qscale:a 8 -ac 1 -ar 22050',
	'-b:a 16k -ac 1 -ar 22050'
]

# ffmpeg -i dave_rogers_deja_vu.mp3 -codec:a libmp3lame -b:a 8k -ac 1 -ar 8000 -af "lowpass=f=1600" -y test.mp3
# ffmpeg -i daft_punk_derezzed.mp3 -codec:a libmp3lame -qscale:a 8 -ac 1 -ar 44100 -y test.mp3

output_roots = []
output_dirs = []
for level in range(0, len(quality_levels)):
	root_dir = 'music_pack_q%s' % (level+1)
	output_dir = '%s/mp3/radio_twlz/' % root_dir
	output_dirs.append(output_dir)
	output_roots.append(root_dir)
	if not os.path.exists(output_dir):
		os.makedirs(output_dir)

all_jobs = []

for root, folders, files in os.walk(src_dir):
	for filename in files:
		in_path = os.path.join(root, filename).replace("\\", "/")

		if 'version_check' in in_path:
			continue

		for level in range(0, len(quality_levels)):
			if target_level != -1 and level != target_level:
				continue
			
			all_jobs.append((in_path, level))
			
			out_path = in_path.replace(src_dir, output_dirs[level])
			parent_dir = os.path.dirname(out_path)
			if not os.path.exists(parent_dir):
				os.makedirs(parent_dir)

def convert_job(id):
	global all_jobs
	global quality_levels
	global output_dirs
	
	while len(all_jobs) > 0:
		try:
			job = all_jobs.pop(1)
			level = job[1]
			in_path = job[0]
			out_path = in_path.replace(src_dir, output_dirs[level])
			
			print("%s LEFT, THREAD %s CONVERT (Q%s): %s" % (len(all_jobs), id, level+1, os.path.basename(in_path)))
			cmd = 'ffmpeg -i "%s" -codec:a libmp3lame %s -y -hide_banner -loglevel error "%s"' % (in_path, quality_levels[level], out_path)
			os.system(cmd)
	
		except IndexError as e:
			break


t1 = datetime.datetime.now()

all_threads = []

for i in range(0, parallel_thread_count):
	t = Thread(target = convert_job, args =(i,))
	t.start()
	all_threads.append(t)
	
for thread in all_threads:
	t.join()

for dir in output_roots:
	shutil.copy(readme, os.path.join(dir, readme))

for dir in output_dirs:	
	dst = os.path.join(dir, version_file_dst)
	if not os.path.exists(os.path.dirname(dst)):
		os.makedirs(os.path.dirname(dst))
	shutil.copy(version_file_src, dst)
	

t2 = datetime.datetime.now()
print("\nFinished in: %s\n" % (t2 - t1))

