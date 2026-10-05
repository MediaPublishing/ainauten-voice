"""Install MuAViC video-only research privately; no compiler or camera needed."""
from __future__ import annotations
import argparse, shutil
from pathlib import Path
from setup_runtime import checked_download, unpack_verified, install_environment, install_face_source, out

AV_PIN = 'e8a6d4202c208f1ec10f5d41a66a61f96d1c442f'
AV_SHA = '1cd85c9630c5aa05978b3e40fb061ac0945c76dd66644a6c79362487e0ed90de'
FAIR_PIN = '272c4c5197250997148fb12c0db6306035f166a4'
FAIR_SHA = '12bcb8cffb67b6f22bfec3e5d75e392392fcc186e9f423f905e71a597c7f9c4a'
MODEL_SHA = '2e6bc47a3251475fb076b7c53934ef5ae6f92656dde480acf740d7bb2c961d1d'
VOCAB_SHA = '02236e90fc09d97336a30b57934b7f14d897e7861dded8029f03b720d3c53ee4'

def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--root',required=True); parser.add_argument('--download',action='store_true'); parser.add_argument('--uv',default='uv'); args=parser.parse_args()
    base=Path(args.root).expanduser().resolve(); base.mkdir(parents=True,exist_ok=True)
    out('start'); install_environment(args.uv,base,Path(__file__).parent/'german',python='3.10')
    vendor=base/'vendor'; vendor.mkdir(exist_ok=True)
    install_face_source(vendor)
    for project,pin,sha,name in [('facebookresearch/av_hubert',AV_PIN,AV_SHA,'av_hubert'),('pytorch/fairseq',FAIR_PIN,FAIR_SHA,'fairseq')]:
        archive=base/(name+'-source.tar.gz')
        checked_download('https://codeload.github.com/'+project+'/tar.gz/'+pin,archive,sha)
        source=unpack_verified(archive,base/('source-'+name+'-'+pin))
        if name=='av_hubert':
            shutil.copytree(source/'avhubert',vendor/'av_hubert/avhubert',dirs_exist_ok=True)
        else:
            shutil.copytree(source/'fairseq',vendor/'av_hubert/fairseq/fairseq',dirs_exist_ok=True)
            (vendor/'av_hubert/fairseq/fairseq/version.py').write_text('__version__ = "0.12.2+'+pin[:7]+'"\n')
        if (source/'LICENSE').exists(): shutil.copy2(source/'LICENSE',vendor/(name+'-LICENSE'))
        out('source_pinned',revision=pin)
    if args.download:
        for name,sha in [('checkpoint_best.pt',MODEL_SHA),('tokenizer.model',VOCAB_SHA)]:
            checked_download('https://dl.fbaipublicfiles.com/muavic/models/de_avsr/'+name,base/name,sha)
            out('model_verified',file=name)
    out('complete',language='de')
if __name__=='__main__': main()
