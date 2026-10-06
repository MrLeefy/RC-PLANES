import json, math, sys
import numpy as np
from PIL import Image
from scipy import ndimage as ndi
R='/tmp/claude-0/ref/'
P=json.load(open('/tmp/claude-0/fit/planforms.json'))
REF={ 'skylark':'c150_3v_w.png','tundra_cub':'cub_3v_w.png','belle51':'p51_3v.png','specter22':'f22_3v.png',
      'brute10':'a10_3v.png','striker16':'f16_3v.png','macharrow':'concorde_3v.png','skyliner':'b747_3v_w.png','cargo130':'c130_3v.png'}
N=240
def ref_mask(fn):
    im=Image.open(R+fn).convert('RGBA'); bgw=Image.new('RGBA',im.size,(255,255,255,255)); bgw.alpha_composite(im); a=np.array(bgw.convert('L'))
    ink=a<200
    ink=ndi.binary_closing(ink,iterations=2)
    bg=~ink
    lab,n=ndi.label(bg)
    # background = component touching the border
    border=set(lab[0,:])|set(lab[-1,:])|set(lab[:,0])|set(lab[:,-1]); border.discard(0)
    out=np.ones_like(bg,dtype=bool)
    for b in border: out&=(lab!=b)
    sil=out | ink
    sil=ndi.binary_fill_holes(sil)
    sil=ndi.binary_opening(sil,iterations=2)
    lab2,n2=ndi.label(sil)
    comps=ndi.find_objects(lab2)
    best=None
    for i,sl in enumerate(comps):
        area=(lab2[sl]==i+1).sum()
        h=sl[0].stop-sl[0].start; w=sl[1].stop-sl[1].start
        if best is None or area>best[0]: best=(area,i+1,sl)
    return lab2==best[1], best[2], lab2, comps
def crop_norm(mask,sl,wh,rot):
    m=mask[sl]
    m=np.rot90(m,rot)
    img=Image.fromarray((m*255).astype('uint8')).resize(wh,Image.BILINEAR)
    return np.array(img)>127
def model_mask(d,wh):
    W,H=wh   # x across (span), z along (length) -> rows = z (nose at top)
    L=d['length']
    span=max([w['span'] for w in d['wings']]+([d['htail']['span']] if d['htail'] else [])+[0.1])
    zs=np.linspace(0,L,H); xs=np.linspace(-span/2,span/2,W)
    m=np.zeros((H,W),bool)
    st=d['fus']
    sz=[s[0] for s in st]; sh=[s[1] for s in st]
    for r,z in enumerate(zs):
        hw=np.interp(z,sz,sh,left=0,right=0) if sz[0]<=z<=sz[-1] else 0
        m[r,np.abs(xs)<=hw]=True
        for w in d['wings']+([d['htail']] if d['htail'] else []):
            half=w['span']/2
            ax=np.abs(xs); s=np.clip(ax/half,0,1)
            le=w['z']+ax*math.tan(math.radians(w['sweep']))
            ch=w['root']+(w['tip']-w['root'])*s
            inside=(ax<=half)&(z>=le)&(z<=le+ch)
            m[r,inside]=True
        for e in d['engines']:
            ex,ez,el,er=e
            if el>0 and abs(abs(ex)-0)>=0:
                m[r,(np.abs(np.abs(xs)-abs(ex))<=er)&(z>=ez)&(z<=ez+el)]=True
    return m
def iou(a,b): return (a&b).sum()/max((a|b).sum(),1)
res={}
for id,fn in REF.items():
    d=P[id]
    mask,sl,_,_=ref_mask(fn)
    wh=(N,N)
    mm=model_mask(d,wh)
    best=(0,0)
    for rot in range(4):
        rm=crop_norm(mask,sl,wh,rot)
        for flip in (False,True):
            r2=rm[::-1] if flip else rm
            v=iou(mm,r2)
            if v>best[0]: best=(v,rot,flip)
    v,rot,flip=best
    rm=crop_norm(mask,sl,wh,rot); rm=rm[::-1] if flip else rm
    out=np.zeros((N,N*3,3),np.uint8)
    out[:,:N,0]=mm*255; out[:,N:2*N,1]=rm*255
    out[:,2*N:,0]=(mm&~rm)*255; out[:,2*N:,1]=(rm&~mm)*255; out[:,2*N:,2]=(mm&rm)*120
    Image.fromarray(out).save('/tmp/claude-0/fit/%s_fit.png'%id)
    res[id]=round(float(v),3)
    print(id,'IoU',round(float(v),3))
json.dump(res,open('/tmp/claude-0/fit/iou.json','w'))
