import json, math, random, sys
import numpy as np
sys.argv=['x']
exec(open('fit.py').read().split("res={}")[0])
random.seed(7)
out={}
for id,fn in REF.items():
    d=json.loads(json.dumps(P[id]))
    mask,sl,_,_=ref_mask(fn)
    wh=(N,N)
    best=(0,0,False)
    mm=model_mask(d,wh)
    for rot in range(4):
        rm=crop_norm(mask,sl,wh,rot)
        for flip in (False,True):
            r2=rm[::-1] if flip else rm
            v=iou(mm,r2)
            if v>best[0]: best=(v,rot,flip)
    v0,rot,flip=best
    rm=crop_norm(mask,sl,wh,rot); rm=rm[::-1] if flip else rm
    base=json.loads(json.dumps(d)); cur=d; curv=v0
    def mut(x,f): return x*(1+random.uniform(-f,f))
    for it in range(400):
        c=json.loads(json.dumps(cur))
        for w in c['wings']:
            k=random.choice(['z','root','tip','sweep']); 
            w[k]=mut(w[k],0.06) if k!='sweep' else w[k]+random.uniform(-3,3)
        if c['htail']:
            h=c['htail']; k=random.choice(['z','root','tip','sweep'])
            h[k]=mut(h[k],0.06) if k!='sweep' else h[k]+random.uniform(-3,3)
        # bounds: within 15 % / 8 deg of the original
        ok=True
        for w,w0 in zip(c['wings'],base['wings']):
            for k in ('z','root','tip'):
                if abs(w[k]/w0[k]-1)>0.15: ok=False
            if abs(w['sweep']-w0['sweep'])>8: ok=False
        if c['htail']:
            for k in ('z','root','tip'):
                if abs(c['htail'][k]/base['htail'][k]-1)>0.15: ok=False
            if abs(c['htail']['sweep']-base['htail']['sweep'])>8: ok=False
        if not ok: continue
        v=iou(model_mask(c,wh),rm)
        if v>curv: cur,curv=c,v
    out[id]={'before':round(v0,3),'after':round(curv,3),'wings':cur['wings'],'htail':cur['htail'],'orig_w':base['wings'],'orig_h':base['htail']}
    print(id,round(v0,3),'->',round(curv,3))
json.dump(out,open('opt.json','w'))
