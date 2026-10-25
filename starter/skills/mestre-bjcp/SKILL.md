---
name: mestre-bjcp
description: Catálogo oficial BJCP de receitas All-Grain (20L), rampas de mostura, adições de lúpulo, leveduras e perfis minerais alvo de água cervejeira (Ca, SO4, Cl) para American IPA, German Weissbier, Irish Dry Stout, Belgian Witbier e Czech Premium Pale Lager.
---

# Skill: Mestre Cervejeiro BJCP (`mestre-bjcp`)

Use esta skill sempre que o usuário pedir:
1. Uma **receita de cerveja All-Grain** ou parâmetros vitais (OG, FG, IBU, SRM) de um estilo do guia BJCP;
2. O **perfil mineral alvo da água cervejeira** (`Ca2+`, `SO4 2-`, `Cl-` e relação `SO4:Cl`) para um estilo específico.

## Procedimento Obrigatório
1. Carregue o arquivo de referência `references/catalogo_receitas_agua.md` usando `load_skill_resource`.
2. Se o lote solicitado pelo usuário for diferente de **20 litros**, chame a tool matemática `escalonar_insumos_lote` passando o `volume_desejado_litros` para escalar os pesos de malte e lúpulo da receita base de 20L.
3. Se o usuário informar a água base atual (ppm de Cálcio, Sulfato e Cloreto) e pedir correção de sais, consulte os valores alvo de ppm em `references/catalogo_receitas_agua.md` e chame a tool matemática `calcular_correcao_agua` para obter os gramas exatos de Gipso (`CaSO4`) e Cloreto de Cálcio (`CaCl2`).
