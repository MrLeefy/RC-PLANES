import json, math
import numpy as np
from PIL import Image
exec(open('side.py').read().split("if __name__")[0])
def upper_ref(m, L_px):
    H,W=m.shape
    cols=np.where(m.any(axis=0))[0]
    x0,x1=cols.min(),cols.max()
    top=np.array([np.argmax(m[:,c]) if m[:,c].any() else H for c in range(W)],float)
    return top,x0,x1
def model_upper(d,zs):
    st=d['fus']; fz=[s[0] for s in st]
    out=[]
    for z in zs:
        y=-1e9
        if fz[0]<=z<=fz[-1]:
            y=np.interp(z,fz,[s[3]+s[2] for s in st])
        for v in d['vtails']:
            le0=v['z']
            # fin top: leading edge at height v.y+height sits at z=le0+height*tan(sweep); fin spans le..le+tip
            for s in np.linspace(0,1,12):
                yy=v['y']+s*v['height']; le=v['z']+s*v['height']*math.tan(math.radians(v['sweep'])); ch=v['root']+(v['tip']-v['root'])*s
                if le<=z<=le+ch: y=max(y,yy)
        out.append(y)
    return np.array(out)
res={}
for id,(fn,box) in SIDE.items():
    ref=side_mask(fn,box)
    d=P[id]; L=d['length']
    best=None
    for flip in (False,True):
        r=ref[:,::-1] if flip else ref
        top,x0,x1=upper_ref(r,0)
        # nose = left end; if nose is at right (flip) handled by trying both: choose the orientation where model-vs-ref error is lower
        n=200
        zs=np.linspace(0,L,n)
        sc=(x1-x0)/L
        cols=(x0+zs*sc).astype(int).clip(0,r.shape[1]-1)
        ref_u=-(top[cols])/sc      # metres (up positive), arbitrary offset
        mod_u=model_upper(d,zs)
        ok=mod_u>-1e8
        # ignore the very first/last 3 % (prop spinners / tail cones)
        sel=ok&(np.arange(n)>n*0.03)&(np.arange(n)<n*0.97)
        diff=(mod_u-ref_u)[sel]; diff=diff-np.median(diff)
        rms=float(np.sqrt((diff**2).mean()))/L
        if best is None or rms<best[0]: best=(rms,flip,diff,sel)
    res[id]=round(best[0]*100,2)
    print(id,'upper-contour RMS % of length:',res[id])
json.dump(res,open('side_rms.json','w'))
