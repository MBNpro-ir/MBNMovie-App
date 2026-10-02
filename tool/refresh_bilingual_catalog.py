"""Import both upstream title languages using the APK's EN/Fa wire values."""
from concurrent.futures import ThreadPoolExecutor
import json,re,sys
from pathlib import Path
from refresh_catalog_index import call,ROOT,OUT

def fetch(kind,page):
    fields={'c':'2','select_dub':'','is_movie':kind}
    fa=call(f'movie_list&pageno={page}',{**fields,'langueg':'Fa'}).get('all') or []
    en=call(f'movie_list&pageno={page}',{**fields,'langueg':'EN'}).get('all') or []
    originals={str(x.get('videos_id') or x.get('id')):str(x.get('title') or '').strip() for x in en}
    rows=[]
    for x in fa:
        ident=str(x.get('videos_id') or x.get('id') or '')
        if not ident:continue
        original=originals.get(ident,'')
        rows.append({'id':ident,'title':str(x.get('title') or ''),'english_title':original,
            'image':str(x.get('thumbnail_url') or ''),'year':str(x.get('year') or ''),
            'rating':str(x.get('imdb') or ''),'kind':kind})
    return rows

def main():
    sys.stdout.reconfigure(encoding='utf-8')
    old={x['id']:x for x in json.loads(OUT.read_text(encoding='utf-8'))}
    merged={}
    checkpoints=ROOT/'tool/bilingual_catalog_pages.jsonl'
    cached={}
    if checkpoints.exists():
        for line in checkpoints.read_text(encoding='utf-8').splitlines():
            x=json.loads(line);cached[(x['kind'],x['page'])]=x['rows']
    with checkpoints.open('a',encoding='utf-8') as log, ThreadPoolExecutor(max_workers=4) as pool:
        for kind in ('movie','serie'):
            for page in range(1,801,4):
                pages=list(range(page,page+4))
                def load(n):return cached.get((kind,n)) if (kind,n) in cached else fetch(kind,n)
                batch=list(pool.map(load,pages))
                for n,rows in zip(pages,batch):
                    if (kind,n) not in cached:
                        log.write(json.dumps({'kind':kind,'page':n,'rows':rows},ensure_ascii=False)+'\n');log.flush()
                    for row in rows:
                        ident=row['id'];value={**old.get(ident,{}),**row}
                        aliases=list(dict.fromkeys([*old.get(ident,{}).get('aliases',[]),row['english_title']]))
                        value['aliases']=[a for a in aliases if a and a!=row['title']]
                        merged[ident]=value
                print(kind,'pages',pages[-1],'titles',len(merged),flush=True)
                if not any(batch):break
            else:raise RuntimeError('Catalog pagination did not finish')
    assert len(merged)>5000, len(merged)
    result=list(merged.values())
    targets=[x for x in result if any('five feet apart' in a.lower() for a in [x['title'],x.get('english_title',''),*x.get('aliases',[])])]
    assert targets,'Five Feet Apart missing from full catalog'
    OUT.write_text(json.dumps(result,ensure_ascii=False,separators=(',',':')),encoding='utf-8')
    print('Imported',len(result),'rows; English:',sum(bool(re.search('[A-Za-z]',x.get('english_title',''))) for x in result),'Five Feet Apart:',[x['id'] for x in targets],flush=True)

if __name__=='__main__':main()
