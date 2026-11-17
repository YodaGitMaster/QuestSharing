"""Export real profession model/UI reference data into a labelled interactive layout preview."""
import json
import pathlib
import sys
ROOT=pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tests'))
from test_professions import game,open_cooking

def plain(v):
    return str(v or '')

def main():
    output=pathlib.Path(sys.argv[1]).resolve()
    g=game('modern',r'''
      QuestDB=nil;NpcDB=nil;ItemDB=nil;ObjectDB=nil;LibQuestieDB=nil;QuestieLoader=nil
      C_TradeSkillUI.GetRecipeSourceText=nil
    ''')
    g.run(r'''
      for _,r in ipairs(NS.cookingReference.recipes)do
       RECIPE_INFO[r.id]={recipeID=r.id,name=r.name,learned=r.id==7751 or r.id==2538 or r.id==2540}
      end
    ''')
    open_cooking(g)
    recipes=[]
    for r in g.eval('NS.professions.recipes()').values():
        ingredients=[]
        for reagent in r.ingredients.values():
            item_id,count=reagent[1],reagent[2]
            ingredients.append(dict(id=item_id,count=count,name=g.eval('NS.professions.itemName')(item_id),farm=list(g.eval('NS.professions.materialLines')(item_id).values())))
        recipes.append(dict(id=r.id,name=r.name,skill=r.skill,known=g.eval('NS.professions.state')(r),shortSource=g.eval('NS.professions.shortSource')(r),sources=list(g.eval('NS.professions.acquisition')(r).values()),ingredients=ingredients))
    professions=[]
    for p in g.eval('NS.professionReference.professions').values():
        ranks=[{key:r[key] for key in ['name','cap','skill','level','method','Alliance','Horde']}for r in p.ranks.values()]
        professions.append(dict(name=p.name,ranks=ranks))
    template=(ROOT/'tools/profession-preview.html').read_text()
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(template.replace('__PROFESSION_DATA__',json.dumps(dict(recipes=recipes,professions=professions),ensure_ascii=False).replace('</','<\\/')))
    print(f'Wrote {output}: {len(recipes)} real model recipes, {len(professions)} professions; learned states are illustrative.')
if __name__=='__main__':main()
