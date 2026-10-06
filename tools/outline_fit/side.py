import json, math, sys
import numpy as np
from PIL import Image
from scipy import ndimage as ndi
R='/tmp/claude-0/ref/'
P=json.load(open('/tmp/claude-0/fit/planforms.json'))
# (file, crop box x0,y0,x1,y1) of the side view in each three-view
SIDE={'skylark':('c150_3v_w.png',(230,60,1060,400)),'tundra_cub':('cub_3v_w.png',(30,45,515,270)),
 'belle51':('p51_3v.png',(130,10,1040,400)),'specter22':('f22_3v.png',(5,375,725,545)),
 'brute10':('a10_3v.png',(262,232,558,305)),'striker16':('f16_3v.png',(232,225,548,325)),
 'macharrow':('concorde_3v.png',(35,10,1270,215)),'skyliner':('b747_3v_w.png',(10,65,990,290)),
 'cargo130':('c130_3v.png',(0,105,295,235))}
N=(320,100)  # w (along z), h (up)
def side_mask(fn,box):
    im=Image.open(R+fn).convert('RGBA'); bgw=Image.new('RGBA',im.size,(255,255,255,255)); bgw.alpha_composite(im)
    a=np.array(bgw.convert('L'))[box[1]:box[3],box[0]:box[2]]
    ink=ndi.binary_closing(a<205,iterations=2)
    lab,n=ndi.label(~ink)
    border=set(lab[0,:])|set(lab[-1,:])|set(lab[:,0])|set(lab[:,-1]); border.discard(0)
    out=np.ones_like(ink)
    for b in border: out&=(lab!=b)
    sil=ndi.binary_fill_holes(out|ink); sil=ndi.binary_opening(sil,iterations=2)
    lab2,n2=ndi.label(sil)
    best=max(range(1,n2+1),key=lambda i:(lab2==i).sum())
    m=lab2==best
    ys,xs=np.where(m); m=m[ys.min():ys.max()+1,xs.min():xs.max()+1]
    return m
def model_side(d,wh):
    W,H=wh
    L=d['length']
    st=d['fus']
    # vertical extent: fuselage centre +- hh, fins, nacelles
    fz=[s[0] for s in st]
    ytop=-1e9; ybot=1e9
    for s in st: ytop=max(ytop,s[3]+s[2]); ybot=min(ybot,s[3]-s[2])
    for v in d['vtails']:
        ytop=max(ytop,v['y']+v['height'])
    ybot=min(ybot,min(s[3]-s[2] for s in st))
    for e in d['engines']:
        ybot=min(ybot,e[4]-e[3]) if len(e)>4 else ybot
    yspan=ytop-ybot
    zs=np.linspace(0,L,W); ys=np.linspace(ytop,ybot,H)
    m=np.zeros((H,W),bool)
    for c,z in enumerate(zs):
        if fz[0]<=z<=fz[-1]:
            yc=np.interp(z,fz,[s[3] for s in st]); hh=np.interp(z,fz,[s[2] for s in st])
            m[(ys<=yc+hh)&(ys>=yc-hh),c]=True
        for v in d['vtails']:
            t=(0)
            # fin: LE at z_le(y)=v.z+ (y-v.y)*tan(sweep); chord root->tip
            for r,y in enumerate(ys):
                if v['y']<=y<=v['y']+v['height']:
                    s=(y-v['y'])/v['height']
                    le=v['z']+(y-v['y'])*math.tan(math.radians(v['sweep']))
                    ch=v['root']+(v['tip']-v['root'])*s
                    if le<=z<=le+ch: m[r,c]=True
    return m
def iou(a,b): return (a&b).sum()/max((a|b).sum(),1)
if __name__=='__main__':
    res={}
    for id,(fn,box) in SIDE.items():
        ref=side_mask(fn,box)
        # orient: nose left; try mirror
        best=(0,False)
        mm=model_side(P[id],N)
        for flip in (False,True):
            r=ref[:,::-1] if flip else ref
            r=np.array(Image.fromarray((r*255).astype('uint8')).resize(N,Image.BILINEAR))>127
            v=iou(mm,r)
            if v>best[0]: best=(v,flip)
        v,flip=best
        r=ref[:,::-1] if flip else ref
        r=np.array(Image.fromarray((r*255).astype('uint8')).resize(N,Image.BILINEAR))>127
        out=np.zeros((N[1],N[0]*3,3),np.uint8)
        out[:,:N[0],0]=mm*255; out[:,N[0]:2*N[0],1]=r*255
        out[:,2*N[0]:,0]=(mm&~r)*255; out[:,2*N[0]:,1]=(r&~mm)*255; out[:,2*N[0]:,2]=(mm&r)*120
        Image.fromarray(out).resize((N[0]*3*2,N[1]*2)).save('/tmp/claude-0/fit/%s_side.png'%id)
        res[id]=round(float(v),3); print(id,round(float(v),3))
    json.dump(res,open('/tmp/claude-0/fit/side_iou.json','w'))
