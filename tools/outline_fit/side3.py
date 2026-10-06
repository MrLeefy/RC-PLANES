import json, math, random, copy
import numpy as np
exec(open('side2.py').read().split("res={}")[0])
random.seed(3)
out={}
for id,(fn,box) in SIDE.items():
    ref=side_mask(fn,box); d=P[id]; L=d['length']
    n=200; zs=np.linspace(0,L,n)
    sel=(np.arange(n)>n*0.03)&(np.arange(n)<n*0.97)
    # reference upper contour for the better orientation
    cand=[]
    for flip in (False,True):
        r=ref[:,::-1] if flip else ref
        top,x0,x1=upper_ref(r,0); sc=(x1-x0)/L
        cols=(x0+zs*sc).astype(int).clip(0,r.shape[1]-1)
        cand.append(-(top[cols])/sc)
    def err(dd,ru):
        mu=model_upper(dd,zs); ok=sel&(mu>-1e8)
        df=(mu-ru)[ok]; df=df-np.median(df); return float(np.sqrt((df**2).mean()))/L
    e0=[err(d,c) for c in cand]; k=int(np.argmin(e0)); ru=cand[k]
    cur=copy.deepcopy(d); ce=e0[k]
    base=copy.deepcopy(d)
    for it in range(600):
        c=copy.deepcopy(cur)
        i=random.randrange(len(c['fus']))
        s=c['fus'][i]; top=s[3]+s[2]; bot=s[3]-s[2]
        top2=top+random.uniform(-1,1)*0.06*s[2]*2
        hh=(top2-bot)/2; yc=(top2+bot)/2
        b=base['fus'][i]
        if abs(hh/b[2]-1)>0.15 or hh<0.003: continue
        s[2]=hh; s[3]=yc
        e=err(c,ru)
        if e<ce: cur,ce=c,e
    out[id]={'before':round(e0[k]*100,2),'after':round(ce*100,2),'fus':cur['fus']}
    print(id,round(e0[k]*100,2),'->',round(ce*100,2))
json.dump(out,open('side_opt.json','w'))
