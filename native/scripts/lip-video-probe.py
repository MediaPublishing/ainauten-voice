#!/usr/bin/env python3
"""Real public-video probe through the identical app worker. Never reads audio."""
import argparse, base64, hashlib, json, os, pathlib, re, select, subprocess, time, unicodedata, uuid
import cv2
p=argparse.ArgumentParser(); p.add_argument('--root',required=True); p.add_argument('--language',choices=['en','de'],required=True); p.add_argument('--video',required=True); p.add_argument('--start',type=float,default=0); p.add_argument('--end',type=float,default=30); p.add_argument('--worker',required=True); p.add_argument('--truth',default=''); p.add_argument('--partial-reference',action='store_true'); p.add_argument('--frames'); p.add_argument('--receipt',required=True); a=p.parse_args()
root=pathlib.Path(a.root); session=str(uuid.uuid4()); capture=cv2.VideoCapture(a.video); fps=capture.get(cv2.CAP_PROP_FPS)
if not capture.isOpened() or fps <= 0: raise RuntimeError('public fixture could not be opened')
capture.set(cv2.CAP_PROP_POS_MSEC,a.start*1000); frames=[]; offset=0
while offset/fps < min(30,a.end-a.start):
 ok,img=capture.read()
 if not ok: break
 # Fit into the app's VGA capture budget, preserving aspect ratio.
 h,w=img.shape[:2]; scale=min(640/w,480/h); img=cv2.resize(img,(round(w*scale),round(h*scale)))
 ok,jpeg=cv2.imencode('.jpg',img,[cv2.IMWRITE_JPEG_QUALITY,65])
 if ok: frames.append({'op':'frame','session':session,'ts_ms':round(offset/fps*1000),'jpeg':base64.b64encode(jpeg).decode()})
 offset+=1
capture.release()
if a.frames: pathlib.Path(a.frames).write_text(json.dumps(frames,separators=(',',':')))
env={'PATH':'/usr/bin:/bin:/usr/sbin:/sbin','HOME':str(pathlib.Path.home()),'PYTHONUNBUFFERED':'1','PYTHONDONTWRITEBYTECODE':'1','PYTORCH_ENABLE_MPS_FALLBACK':'1','OMP_NUM_THREADS':'4'}
start=time.monotonic(); child=subprocess.Popen([str(root/a.language/'.venv/bin/python'),'-u',a.worker,'--root',str(root),'--language',a.language],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True,env=env)
try:
 def reply():
  if not select.select([child.stdout],[],[],120)[0]: raise TimeoutError('research worker response exceeded 120 seconds')
  return json.loads(child.stdout.readline())
 ready=reply(); warm=time.monotonic()-start
 if ready.get('type')!='ready': raise RuntimeError('real model did not become ready: '+str(ready))
 begin=time.monotonic()
 for item in [{'op':'begin','session':session,'ts_ms':0}]+frames+[{'op':'finish','session':session}]:
  child.stdin.write(json.dumps(item,separators=(',',':'))+'\n')
 child.stdin.flush(); result=reply(); latency=time.monotonic()-begin
 normalize=lambda value: re.findall(r"[^\W_]+",unicodedata.normalize('NFC',value).lower())
 truth=normalize(a.truth); words=normalize(result.get('text',''))
 row=list(range(len(words)+1))
 for i,t in enumerate(truth,1):
  nxt=[i]
  for j,w in enumerate(words,1): nxt.append(min(nxt[-1]+1,row[j]+1,row[j-1]+(t!=w)))
  row=nxt
 receipt={'language':a.language,'video_sha256':hashlib.sha256(pathlib.Path(a.video).read_bytes()).hexdigest(),'video_only':True,'frame_count':len(frames),'duration_seconds':offset/fps,'model_ready_seconds':round(warm,3),'inference_seconds':round(latency,3),'result':result,'reference':a.truth,'reference_is_partial':a.partial_reference,'normalized_word_error_rate':row[-1]/len(truth) if truth and not a.partial_reference else None,'reference_word_coverage':len(set(truth)&set(words))/len(set(truth)) if truth else None,'scope':'one public clip, not personal-camera acceptance'}
 pathlib.Path(a.receipt).write_text(json.dumps(receipt,ensure_ascii=False,indent=2)); print(json.dumps(receipt,ensure_ascii=False))
finally:
 child.terminate()
 try: child.wait(timeout=3)
 except subprocess.TimeoutExpired: child.kill(); child.wait()
