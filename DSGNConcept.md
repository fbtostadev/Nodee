# DSGNConcept — Filosofia de Design do Nodee

> Documento **vivo**. Registra a linguagem visual do Nodee e sua evolução. Onde o
> `CLAUDE.md` cobre **como construir** e o PRD cobre **o quê / por quê**, este
> arquivo cobre **com que aparência e com que sensação** — a estética e os
> princípios que mantêm a superfície coerente conforme novos componentes nascem.
>
> Regra de ouro: **antes de inventar um tratamento visual novo, herde um
> existente.** A linguagem só vale se for reaproveitada. Cada efeito documentado
> aqui é um *token de comportamento*, não um enfeite pontual.

---

## 0. Onde isto vive na hierarquia de decisão

1. **PRD** (`Documents/Academy/.../product-reference-document-v3.docx`) — comportamento de produto.
2. **CLAUDE.md** — arquitetura, stack, convenções de build.
3. **DSGNConcept.md** (este) — linguagem visual e estética.
4. **`Theme.swift`** — a fonte de verdade *executável* dos tokens. Quando este doc
   e o `Theme` divergirem em números, o `Theme` vence (e este doc deve ser
   atualizado). Constantes de motion/geometria do painel já moram lá; cores
   semânticas e receitas de efeito ainda estão inline nos componentes e são
   candidatas naturais a migrar para o `Theme` à medida que se repetem.

---

## 1. Princípios estéticos (derivados dos princípios de produto)

A estética do Nodee não é decorativa — ela serve aos seis princípios de produto
do `CLAUDE.md`. Em termos visuais, isso se traduz em:

1. **Vidro escuro sobre o sistema.** O Nodee mora no Notch e flutua sobre o
   desktop. A superfície é um **vidro escuro** (`.ultraThinMaterial` velado por
   preto) com bordas de luz finas. Nunca um bloco opaco chapado — ele pertence ao
   ambiente do macOS, não o cobre.
2. **A luz comunica, não enfeita.** Todo brilho (shimmer, glow, halo) carrega
   significado: confirma uma ação, sinaliza um estado, aponta uma direção. Se um
   efeito não comunica nada, ele não entra.
3. **Cor é semântica antes de ser decoração.** Um tom não é escolhido por gosto;
   ele *diz* o tipo da operação (mover / copiar / descartar / erro). Ver §2.
4. **Movimento é físico, não cosmético.** Springs bem amortecidas, sem overshoot
   gratuito. As coisas *emergem*, *assentam* e *retraem* — não piscam. O painel
   "cresce do Notch"; a toast "respira"; o shimmer "varre" ou "gira".
5. **Feedback preditivo e reversível.** A superfície mostra o resultado antes ou
   logo após a ação (nó fantasma no drag, toast com Undo), sempre com saída.
6. **Densidade legível.** Tipografia pequena e firme (SF, 10–12pt), pesos
   `.medium`/`.semibold`, branco em opacidades graduadas (0.4 → 0.9) para
   hierarquia sem precisar de mais cor.

---

## 2. Tokens semânticos de cor

Os accents são o vocabulário cromático do app. Hoje vivem inline (sobretudo em
`ToastView.swift` e `BrowserToolbar.swift`); a intenção é consolidá-los no
`Theme`. Os valores canônicos:

| Papel semântico | Uso | RGB (0–1) | Hex aprox. |
|---|---|---|---|
| **Ice-blue** (`accent` padrão) | Mover, navegar, ação primária, seleção, estado neutro/positivo | `0.55, 0.80, 1.00` | `#8CCCFF` |
| **Amber** | Copiar / duplicar | `1.00, 0.78, 0.38` | `#FFC761` |
| **Red** | Descartar (Lixeira) e erro | `1.00, 0.38, 0.38` | `#FF6161` |
| **Red (chip)** | Variante levemente mais clara para chip de destino "Lixeira" | `1.00, 0.42, 0.42` | `#FF6B6B` |
| **White** | Luz de borda, texto, realce de apex no shimmer | `1.00, 1.00, 1.00` (com opacidade) | `#FFFFFF` |

**Regra de mapeamento (canônica — `ToastView.accent`):**

```
isError            → Red
context.kind == .trashed → Red
context.kind == .copied  → Amber
move / default / nil     → Ice-blue
```

O ice-blue é o **tom da casa**: na ausência de uma intenção específica (mover,
navegar, selecionar, copiar caminho), é ele que aparece. Amber e red são reservas
semânticas — só surgem para *copiar* e *descartar/erro*. Não introduza um quinto
accent sem que ele represente uma classe de operação genuinamente nova.

---

## 3. A superfície de vidro escuro (a base de tudo)

Todo elemento flutuante (toast, e futuros popovers / cards / HUDs) compartilha a
mesma receita de superfície. É o que faz um componente "parecer Nodee".

**Composição de camadas (de baixo para cima), conforme `ToastView`:**

1. **Vidro:** `RoundedRectangle(cornerRadius:, style: .continuous)` preenchido com
   `.ultraThinMaterial`.
2. **Véu escuro:** overlay do mesmo shape com `.black.opacity(0.55)` — escurece o
   material para o tema dark e dá contraste ao texto branco.
3. **Borda de luz (fixa):** `strokeBorder(Color(white: 1.0, opacity: 0.19), lineWidth: 1)`
   — o fio de luz estática que define a aresta do vidro.
4. **Borda de luz (viva):** a borda de **shimmer** angular por cima (ver §4).
5. **Clip:** `clipShape` no mesmo shape, aplicado **antes** das sombras, para o
   conteúdo não vazar enquanto o container redimensiona — mas deixando as sombras
   renderizarem por fora.
6. **Glow + elevação:** a pilha de sombras (ver §5).

**Raio de canto:** `.continuous` sempre (curvatura squircle, idioma macOS). Pílula
em estado compacto (`20`), card em estado expandido (`16`). Use `.continuous` em
qualquer canto arredondado novo.

**Tipografia da superfície:** SF system, 10–12pt. Mensagem em `12pt .medium`
`white.opacity(0.9)`; rótulos de ação em `12pt .semibold` no accent; metadados em
`10–11pt` com branco 0.4–0.85 conforme a hierarquia.

---

## 4. Shimmer — o efeito-assinatura  ⭐

O **shimmer** é o ponto sólido da linguagem: uma borda de luz que **varre** ou
**gira** ao redor de um elemento. É a forma do Nodee dizer "algo aconteceu aqui" ou
"este elemento está vivo". Já existe em **duas variantes** com propósitos
distintos — e essa dualidade *é* a gramática a ser expandida.

### 4.1 Anatomia comum

Um shimmer é sempre:

- Uma `RoundedRectangle(...).strokeBorder(AngularGradient(...), lineWidth:)`
  sobreposta ao elemento.
- O `AngularGradient` tem **um `center`** e um **`angle` animável**. Animar o
  ângulo = girar o arco de luz ao redor da borda.
- A paleta do gradiente é uma sequência de paradas (`stops`) que sobem do
  transparente até um **apex** e voltam ao transparente — um **arco em forma de
  sino**. O apex costuma levar um toque de **branco** sobre o accent, para o
  brilho "estourar" levemente no pico.
- **Sem fronteiras `.clear` duras** no meio do arco e com **muitas paradas**
  (8–13): isso elimina o flicker de hotspot angular quando o gradiente gira.
- O fim da lista de cores deve **casar com o começo** (mesmo valor a 0° e 360°)
  para que a emenda da rotação seja invisível.

### 4.2 Variante A — Shimmer **orbital contínuo** (ToastNotification)

> Propósito: enquanto a toast está presente, ela **respira luz**. O efeito é
> ambiente, perpétuo e calmo — sinaliza "este objeto está ativo e aguardando você".

Fonte: `ToastView.swift`.

- **Paleta (`glowColors`, 8 stops):**
  `[.clear, accent·0.0, accent·0.32, white·0.18, accent·0.20, accent·0.08, .clear, .clear]`
  O apex é o `accent·0.32` seguido de `white·0.18` — o pulso de cor com o realce
  branco logo atrás.
- **Movimento:** `angle` de `0 → 360°`, `.linear(duration: 5).repeatForever(autoreverses: false)`.
  Uma volta lenta a cada **5s**, infinita, sempre no mesmo sentido. Linear (não
  spring) porque rotação perpétua não deve acelerar/desacelerar.
- **Traço:** `lineWidth: 1`, sobre a borda de luz fixa de 0.19.
- **Cor:** segue o `accent` semântico da toast (§2) — uma toast de Lixeira gira
  em vermelho, uma de cópia em âmbar, as demais em ice-blue.

### 4.3 Variante B — Shimmer **de passagem única** (breadcrumb, copy-path)

> Propósito: confirmar um **evento pontual** (o usuário copiou o caminho). É um
> "anel de loading que completa uma volta e some" — deliberado, com começo, meio e
> fim. Não fica girando: aparece, dá uma volta, dissolve.

Fonte: `BrowserToolbar.swift` (`fireCrumbShimmer`).

- **Paleta (`crumbGlowColors`, 13 stops):** sino largo (~120° de cobertura),
  subida gradual `0.00 → 0.28` (apex), com `white·0.09` no pico, e descida
  simétrica de volta a `0.00`. Pico baixo (0.28) e sem `.clear` duro = varredura
  suave sem flicker.
- **Movimento (sequência orquestrada):**
  1. Começa em **225°** (diagonal inferior-esquerda) — entra "de um canto", lê
     como direcional, não arbitrário.
  2. **Fade-in:** `opacity 0→1` em `easeIn 0.50s` — a borda materializa
     gentilmente.
  3. **Giro:** `angle 225° → 225°+360°` em `easeInOut 3.2s` — começa lento
     (loading), ganha momento, desacelera ao fim (completo). **Uma** passada
     horária, unidirecional.
  4. **Fade-out:** começa em `2.2s` (`easeOut 1.0s`), sobreposto à desaceleração,
     para a borda "pousar" ao completar em vez de cortar seco.
- **Cor:** ice-blue (cópia de caminho é ação neutra/positiva).
- **Disparo:** imperativo, via função, em resposta à ação do usuário (não no
  `onAppear`). Envolve o caminho **inteiro** como uma unidade.

### 4.4 Quando usar qual

| Você quer comunicar… | Variante | Motion |
|---|---|---|
| "este objeto flutuante está ativo / aguardando" (estado contínuo) | **A — orbital** | linear, repeatForever, lento (~5s/volta) |
| "esta ação acabou de acontecer" (evento pontual) | **B — passagem única** | easeInOut, uma volta, com fade-in/out |

**Anti-padrões:**
- Não use shimmer em elementos de fundo persistentes (toolbar inteira, listas):
  vira ruído e mata o significado. Shimmer é pontuação, não preenchimento.
- Não pisque (`autoreverses` rápido). O shimmer **varre** ou **gira**; nunca
  estrobosca.
- Não empilhe dois shimmers no mesmo elemento.

---

## 5. Glow — profundidade e halo de cor

Se o shimmer é a luz que *se move*, o **glow** é a luz que *fica* — o halo que
eleva o objeto do fundo e tinge o ambiente com o accent.

### 5.1 Glow em camadas da ToastNotification

Fonte: `ToastView.swift`. Três sombras empilhadas, cada uma com um papel:

```
.shadow(color: accent.opacity(0.18), radius: 16, y: 0)   // 1 · halo de COR — tinge o entorno com a semântica
.shadow(color: white.opacity(0.06),  radius: 28, y: 2)   // 2 · bloom difuso — alarga o brilho, suaviza a borda
.shadow(color: .black.opacity(0.45), radius: 12, y: 6)   // 3 · elevação — sombra de contato, descola do fundo
```

A ordem importa conceitualmente: **(1) cor → (2) bloom → (3) profundidade**. O
halo de cor é o que faz uma toast vermelha "sangrar" vermelho no entorno e uma de
cópia irradiar âmbar — o glow herda o mesmo `accent` semântico do shimmer, então
**cor de borda viva e cor de halo são sempre a mesma**. Essa coerência (shimmer e
glow falando o mesmo tom) é parte da assinatura.

### 5.2 Glow orbital (canvas — arquivado, mas é precedente da linguagem)

Fonte: `FileNodeView.swift` (`orbitalGlow`). Uma pasta expandida ganha
`shadow(color: accent·0.3, radius: 18)` para se ler como centro gravitacional
"ligado". Mesmo princípio: **glow = estado ativo, na cor semântica do objeto.**
Quando o canvas voltar como 3º modo, este é o tratamento a manter.

### 5.3 Diretrizes de glow

- Halo de cor: `accent.opacity(0.15–0.32)`, `radius 16–18`, `y: 0` (cor irradia
  para todos os lados, não "cai").
- Elevação (preta): `radius 6–12`, `y` positivo pequeno (2–6) — sombra de contato
  que ancora o objeto.
- Bloom branco difuso (opcional, para objetos "premium"/flutuantes): opacidade
  muito baixa (~0.06), raio grande (~28).
- Estado **inativo** = glow `.clear` (ver `OrbitalGlowModifier`). O glow aparece
  e some com o estado; anime a transição, não corte.

---

## 6. Movimento — o vocabulário de animação

As constantes de motion canônicas vivem em `Theme.swift`. Estética por trás dos números:

- **Painel emerge do Notch** (`panelOpen` / `panelClose`): springs bem amortecidas
  (`dampingFraction 0.82`/`0.90`), **sem overshoot vertical** — cresce e assenta.
  Revelação **faseada**: forma primeiro, conteúdo e sombra depois
  (`panelContentRevealDelay`, `panelShadowRevealDelay`), para ler como um bloco
  sólido único, não três camadas abrindo juntas.
- **Toast expande no hover** (350ms de dwell → `timingCurve(0.22,1,0.36,1)` em
  0.42s): bezier ease-out **sem overshoot de spring**; container e fade do conteúdo
  compartilham a mesma curva, então o detalhe sobe em sincronia. Recolhe em
  `timingCurve(0.4,0,0.2,1)` 0.26s.
- **Springs orbitais / breadcrumb** (`response ~0.34–0.45`, `damping ~0.72–0.82`):
  bloom/implosão com leve vida, mas controlado.
- **Princípio geral:** estados contínuos → `linear`/`repeatForever`; transições de
  estado → `spring` amortecido ou `timingCurve` ease-out; eventos pontuais →
  `easeIn`/`easeInOut`/`easeOut` orquestrados. **Overshoot só quando ele significa
  algo** (energia, vida); para superfícies "sérias" (painel), zero overshoot.

---

## 7. Como expandir a linguagem para um novo componente

Checklist ao desenhar qualquer superfície/efeito novo:

1. **É flutuante sobre o sistema?** Use a superfície de vidro escuro do §3
   (material + véu preto + borda de luz 0.19 + cantos `.continuous`). Não
   reinvente o fundo.
2. **Precisa de cor?** Tire do vocabulário semântico do §2. Se nenhum papel serve,
   pergunte se é mesmo uma classe de operação nova antes de criar um accent.
3. **Quer brilho?** Decida: estado contínuo → shimmer orbital (§4.2) ou glow
   estático (§5); evento pontual → shimmer de passagem única (§4.3). Reaproveite a
   anatomia do `AngularGradient` (sino, muitas paradas, apex com toque de branco,
   emenda 0°≡360°).
4. **Coerência shimmer↔glow:** se o componente tem ambos, **a mesma cor semântica**
   alimenta os dois.
5. **Movimento:** siga o §6. Estados contínuos lineares; transições amortecidas;
   sem flicker, sem estrobo.
6. **Densidade e tipografia:** SF 10–12pt, branco em opacidades graduadas para
   hierarquia antes de recorrer a mais cor.
7. **Documente aqui.** Toda variante nova de shimmer/glow/superfície entra no §9
   (changelog) com sua data e seu propósito. A linguagem só permanece coerente se
   for escrita. Componentes com vocabulário próprio ganham uma seção de referência
   consolidada (ver §8, DotMatrixIndicator).

---

## 8. DotMatrixIndicator — indicador de status data-driven

> Referência **consolidada** do componente (estado atual). O §9 (changelog) guarda
> o histórico de como chegamos aqui; esta seção é a fonte autoritativa de **o que
> ele é hoje**. Fonte: `DotMatrixIndicator.swift`.
>
> Pequena **íris de luz** (anéis concêntricos de pontos — `standardIris`: centro
> + 6 + 12 = 19 pontos) cujo comportamento é inteiramente ditado por dados. A
> geometria é fixa; os dados (frames de intensidade, um por ponto) são o motor. A
> mesma view vira spinner, confirmação ou alarme — sem mudar código de view. A
> **malha quadrada** 5×5 sobrevive como fallback legado (`layout: nil`).

### 8.1 Pixel de intensidade (o fundamento)

Cada pixel carrega um **brilho 0…1**, não um booleano on/off. Luz binária só
pisca; intensidade *flui* — um cometa tem cabeça 1.0 e rastro decaindo
(1.0 → 0.45 → 0.20). Poucos frames + a spring por pixel (`dotMatrixPixelSpring`)
tecem movimento contínuo. É o que torna o componente "tela de luz", não "LED
piscando". Em malha densa, intervalo curto + spring fundem os passos num arco
contínuo.

### 8.2 Arquitetura

- **`DotMatrixSequence`** — filmstrip de frames de intensidade (`[[Double]]`) +
  `interval`, `loops`, `flashFrames` (apex branco), `accentOverride`. Init de
  conveniência `boolFrames:` para máscaras pontuais. As animações são **geradores
  procedurais por dimensão** (8.3), não floats hand-tuned.
- **`DotMatrixState`** — intenção de alto nível: `.idle .loading .success .error
  .move .copy .trash .syncing .pinned .custom(seq)`. Cada caso mapeia para um
  gerador; `.custom` aceita sequência arbitrária.
- **`DotMatrixEngine`** (`@Observable @MainActor`) — playback por timer
  (`Task.sleep`): avança `currentFrame`, resolve o accent, marca `isFlashing` nos
  `flashFrames`.
- **`DotMatrixLayout`** — a geometria radial: lista ordenada de `DotMatrixDot`
  (`point` normalizado + `ring` + `angle`). A ordem dos pontos é a indexação dos
  frames (substitui o row-major quadrado). `standardIris` = centro + 6 + 12.
  Helpers `ring(of:)`, `outerRingIndices`, `normalizedRingSpacing` — os análogos
  radiais de `ring(idx,n)`/`perimeter(n)`.
- **`DotMatrixIndicator`** (View) — por padrão posiciona os pontos da íris via
  `.position` (`Circle` por ponto); `layout: nil` cai no `LazyVGrid` quadrado
  legado. Footprint fixado por `extent` (densificar só diminui o ponto). Glow
  semântico que **respira** com o pico de intensidade.

### 8.3 Vocabulário de verbos (o léxico de movimento)

Cada estado é um *verbo de luz* cuja **forma do movimento é a semântica**. Todos
procedurais sobre a íris (sufixo `…Radial` no código). Quatro primitivas: **anel
externo** (orbit), **anéis concêntricos** (converge/bloom/breathe), **banda em y**
(os lineares — cada ponto tem `point.y` real, então "subir/descer" é uma faixa de
brilho varrendo y, não um índice de linha) e o **jolt radial** (erro):

| Verbo | Estado / uso | Primitiva | Forma | Cor |
|---|---|---|---|---|
| `orbitRadial` | `.loading` | anel externo | cometa único c/ rastro | ice-blue |
| `dualOrbitRadial` | copy-path | anel externo | 2 cometas a 180° (point-symmetric) | ice-blue |
| `convergeRadial` | `.success` | anéis | rim → centro + flash branco | accent |
| `dualOrbitDoneRadial` | copy-path | anéis | colapso + bloom **verde** | green |
| `liftRadial` | `.move` | banda em y | banda sobe com esteira | ice-blue |
| `cascadeRadial` | `.copy` | banda em y | cópia desce, fonte fica acesa | amber |
| `dissolveRadial` | `.trash` | banda em y | front varre p/ baixo, afunda | red |
| `breatheRadial` | `.syncing` | anéis | swell do centro, contínuo | base |
| `shudderRadial` | `.error` | jolt radial | anéis flamejam + jitter + flash | red |
| `bloomRadial` | `.pinned` | anéis | centro explode pra fora | ice-blue |

### 8.4 Densidade — padrão único, footprint fixo

- **`DotMatrixLayout.standardIris`** (centro + 6 + 12 = 19 pontos) rege o app
  inteiro. A **malha quadrada 5×5** (`standardDimension`) é fallback legado, só
  para chamadas com `layout: nil` — não troca animada.
- **`extent`** fixa o lado total — densificar só diminui o ponto, nunca cresce o
  componente.
- **Layout é constante por indicador, não algo a transicionar.** Trocar geometria
  no meio da vida reflowa e fica feio; loading e conclusão de um mesmo indicador
  partilham uma única íris (ex.: copy-path `dualOrbitRadial` → `dualOrbitDoneRadial`).

### 8.5 Cor & flash

- Accent resolvido na ordem **`sequence.accentOverride` > `state.semanticAccent` >
  `accent` base da view**. Verbos neutros (loading/move/success/syncing/pinned/
  breathe) herdam o base; copy = amber, trash/error = red têm cor própria.
- **`flashFrames`** — frames que estouram em **branco** (apex positivo, §4).
  Reservado a verbos de confirmação (converge/lift/cascade/bloom); erro e trash
  nunca flasham branco.
- **`DotMatrixPalette.green` (#73EB8F)** — accent **transiente de conclusão**, não
  um 5º accent de repouso (§2). Só no beat final de uma animação (`dualOrbitDone`).

### 8.6 Padrão de duas fases (liveness)

Para um indicador que precisa **continuar vivo** depois de anunciar:

1. **Anúncio** — o verbo semântico toca uma vez (one-shot).
2. **Assentamento** — transita para um estado contínuo (`breathe` na toast) ou
   volta ao repouso (ícone `link` no copy-path).

Na toast isso casa com o shimmer da borda que respira perpetuamente (§4.2): o
indicador anuncia → respira na cor da operação, em lockstep com borda e glow
(§5.1, mesmo tom). **Surgimento faseado** (§6, forma primeiro): durante o slide-in
da pill o indicador fica apagado; ao a pill assentar ele **floresce** (scale +
opacity) e só então anuncia — a luz "acorda com" a toast, não chega pronta.

### 8.7 Integrações

- **`ToastView`** — verbo por operação (`moved→move`, `copied→copy`,
  `trashed→trash`, erro → error) → `breathe`. `extent: 16`, `showGlow: false`,
  accent sincronizado com shimmer/glow.
- **`BrowserToolbar`** (copy-path) — **no lugar** do ícone `link`: `dualOrbitRadial`
  (íris, ciclo 0.42s) → `dualOrbitDoneRadial` (bloom verde) → volta ao `link`.
  `extent: 18`. Complementado pelo shimmer de passagem única do breadcrumb (§4.3).

### 8.8 Tokens (`Theme`)

`dotMatrixExtent` (14), `dotMatrixFrameInterval` (0.18), `dotMatrixPixelSpring`
(response 0.26, damping 0.80), `dotMatrixGlowRadius` (14), `dotMatrixActiveOpacity`
(1.0), `dotMatrixTrailDecay` (0.45). O diâmetro do ponto na íris deriva de
`normalizedRingSpacing · extent · 0.8`. `dotMatrixGapRatio`/`dotMatrixCornerRatio`
valem só para o fallback quadrado.

### 8.9 Como adicionar um estado futuro

Novo status = nova sequência **sem tocar a view**: prefira um gerador procedural
(escala por dimensão) ou use `.custom(DotMatrixSequence(...))`. Se o indicador
precisa viver após anunciar, aplique o padrão de duas fases (8.6). Cor: tire do
§2; se nenhum papel serve, questione se é uma classe de operação genuinamente nova
antes de criar um accent.

---

## 9. Evolução / changelog de design

> Registre aqui cada decisão estética relevante — o que mudou, por quê, e onde
> vive no código. Converta datas relativas em absolutas. As entradas de
> DotMatrix abaixo são **histórico**; o estado atual consolidado vive no §8.

- **2026-06-12 — Documento criado.** Formalização da linguagem visual a partir do
  estado atual do MVP. Pilar: **shimmer + glow das ToastNotifications**
  (`ToastView.swift`) como efeito-assinatura, com a variante de **passagem única**
  já replicada no shimmer de copy-path do breadcrumb (`BrowserToolbar.swift`).
  Precedente de glow de estado ativo no canvas arquivado
  (`FileNodeView.orbitalGlow`). Vocabulário semântico de cor (ice-blue / amber /
  red) consolidado neste doc; candidato a migrar para `Theme.swift`.
- **2026-06-13 — DotMatrixIndicator.** Componente de indicação de status baseado
  em Animação Orientada a Dados: grade 3×3 com máscara cruciforme configurável.
  A geometria é estática (pixels fixos); os dados (matrizes de booleans) ditam
  o comportamento. Estados pré-definidos: `loading` (rotação orbital, ice-blue),
  `success` (convergência + flash branco), `error` (pulso em X, red), `idle`.
  Spring por pixel (`response: 0.30, damping: 0.78`) dá vida sem bounce
  exagerado. Glow semântico segue §5. Aceita sequências custom para estados
  futuros sem tocar na view. Fonte: `DotMatrixIndicator.swift`.
- **2026-06-13 — DotMatrix: pixel de intensidade + verbos de luz.** Revisão do
  modelo de animação do `DotMatrixIndicator`. Os frames deixaram de ser booleanos
  (`[[Bool]]`, aceso/apagado) e passaram a carregar **intensidade por pixel**
  (`[[Double]]`, brilho 0…1). Motivo: luz binária só pisca; intensidade *flui* —
  um cometa ganha rastro decaindo (head 1.0 → 0.45 → 0.20), e a spring por pixel
  tece poucos frames em movimento contínuo. Isso transforma o componente de "LEDs
  piscando" em "tela de luz".
  Sobre essa base nasce um **vocabulário de movimento** — cada estado é um *verbo
  de luz* com forma própria, e a forma do movimento **é** semântica (sobe = mover,
  cai = copiar/descartar). Mapa para as operações do app e o accent do §2:
  `orbit` (loading/scan · ice-blue), `converge` (success · accent, flash branco),
  `lift` (mover · ice-blue, luz sobe com esteira), `cascade` (copiar/duplicar ·
  amber, fonte fica acesa enquanto a cópia desce → duas instâncias), `dissolve`
  (Lixeira · red, afunda e some por baixo), `breathe` (live/FSEvents/aguardando ·
  ice-blue dim, swell contínuo do centro), `shudder` (erro · red, X flameja e
  treme), `bloom` (fixar projeto/criado · ice-blue, centro explode pra fora).
  Flash branco generalizado via `flashFrames: Set<Int>` na sequência (apex
  positivo; reservado a verbos de confirmação, não a erro/trash). Glow do §5 agora
  **respira** — opacidade do halo modulada pelo pico de intensidade do grid.
  O `ToastView` passou a rotear `moved → .move`, `copied → .copy`,
  `trashed → .trash` (antes tudo caía em `.success`/`.error`), então cada toast
  conta a operação que aconteceu, não só "deu certo". API da view inalterada;
  `DotMatrixSequence` ganhou init de conveniência `boolFrames:` para máscaras
  pontuais. Fonte: `DotMatrixIndicator.swift`, `Theme.swift`, `ToastView.swift`.
- **2026-06-13 — Copy-path: loading órbita-dupla in-place + conclusão verde.**
  O feedback de copiar caminho saiu de "indicador ao lado do botão" para tocar
  **no lugar do ícone**: o glyph `link` cede o espaço (34×30) ao `DotMatrixIndicator`
  (`pixelSize: 5`) e volta ao fim. O movimento é **simétrico e cíclico** —
  `dualOrbit`: dois cometas a 180° no perímetro (na malha 3×3, offset +4 cai na
  diagonal oposta, então o par é point-symmetric pelo centro). Coreografia:
  `dualOrbit` (~0.72s, um ciclo, ice-blue) → `dualOrbitDone` (cometas implodem ao
  centro e **florescem em verde**, ~1.0s) → `idle`. A mudança de cor na conclusão
  é deliberada: o verde sinaliza "concluído" sem precisar de um glyph. Novo token
  `DotMatrixPalette.green` (#73EB8F) — accent **transiente de conclusão**, não um
  quinto accent semântico para estados em repouso (§2); reservado ao beat final de
  uma animação. Candidato a formalizar se "concluído" virar classe recorrente.
  O shimmer de passagem única do breadcrumb (§4.3) foi mantido — complementa,
  envolvendo o caminho inteiro enquanto o botão confirma localmente. Fonte:
  `DotMatrixIndicator.swift` (`dualOrbit`/`dualOrbitDone`), `BrowserToolbar.swift`.
- **2026-06-13 — DotMatrix: densidade variável com footprint fixo + ritmo mais
  rápido.** O componente deixou de ser hardcoded em 3×3 e passou a ser
  **agnóstico à dimensão**: a malha (3×3, 5×5, 7×7…) é definida pela sequência que
  toca, e a view deriva a dimensão de `√(nº de células)` do frame atual. O tamanho
  é fixado por `extent` (lado total constante) — pixel e gap são derivados dele,
  então **densificar só diminui o pixel, nunca aumenta o componente**. Em malha
  densa, o intervalo curto + a spring por pixel fundem os passos num **arco de luz
  contínuo** (em vez de pontos discretos) — quanto mais densa, mais "tela" e menos
  "LED". `dualOrbit`/`dualOrbitDone` viraram **geradores por dimensão**
  (`dualOrbit(dimension:cycle:)`, `dualOrbitDone(dimension:)`): perímetro e colapso
  concêntrico calculados para qualquer n. O copy-path agora usa 5×5 com ciclo de
  0.42s (loading ~0.46s → bloom verde ~0.62s ≈ 1.1s total, antes ~1.7s). API da
  view trocou `pixelSize` por `extent`; `gridMask` virou opcional (`nil` = malha
  inteira). Tokens novos no `Theme`: `dotMatrixExtent`, `dotMatrixGapRatio`,
  `dotMatrixCornerRatio`. Fonte: `DotMatrixIndicator.swift`, `Theme.swift`,
  `BrowserToolbar.swift`.
- **2026-06-13 — Densidade fixa por indicador: 5×5 padrão, 3×3 fallback.**
  Mudar de densidade no meio da vida de um indicador reflowa o `LazyVGrid` e fica
  feio — então densidade deixou de ser algo a *transicionar* e virou uma constante
  por indicador. **5×5 é o padrão** (default `dimension: 5` em `dualOrbit`/
  `dualOrbitDone`); 3×3 é fallback de compilação, não troca animada ao vivo. No
  copy-path, uma única fonte de verdade (`copyDotDensity`) alimenta loading e
  conclusão, garantindo que o hand-off `dualOrbit → dualOrbitDone` nunca cruze
  dimensões. Fonte: `DotMatrixIndicator.swift`, `BrowserToolbar.swift`.
- **2026-06-13 — Vocabulário inteiro em densidade única (`standardDimension = 5`).**
  Antes só o copy-path era 5×5; os verbos semânticos (orbit, converge, lift,
  cascade, dissolve, breathe, shudder, bloom, idle) eram 3×3 hand-authored — duas
  densidades convivendo no app (ex.: o ToastView mostrava 3×3). Agora **todos os
  verbos são geradores procedurais por dimensão**, com default `standardDimension`
  (5×5) — uma constante única que rege a malha do componente. As 8 animações foram
  reconstruídas a partir de 4 primitivas que escalam para qualquer n: **perímetro**
  (orbit/dualOrbit), **anéis concêntricos** (converge/bloom/breathe/dualOrbitDone),
  **linhas** (lift/cascade/dissolve) e a **diagonal X** (shudder). Benefício duplo:
  consistência visual (uma densidade no app inteiro, sem hand-off cruzando malhas)
  e manutenção (motion descrito por regra, não por 25 floats hand-tuned). 3×3 segue
  acessível como fallback explícito (`dimension: 3`). O indicador do ToastView subiu
  para `extent: 16` para o 5×5 respirar. Fonte: `DotMatrixIndicator.swift`,
  `ToastView.swift`, `BrowserToolbar.swift`.
- **2026-06-13 — Conformidade de liveness na ToastNotification.** O indicador da
  toast tocava o verbo **one-shot** e morria num frame apagado — deixando um vão
  escuro ao lado do texto enquanto a borda continuava respirando luz para sempre
  (§4.2). Gap de conformidade: a toast é um objeto vivo, mas seu indicador líder
  apagava. Correção em **duas fases** (mesma gramática do copy-path): o verbo
  **anuncia** a operação uma vez (move/copy/trash/error → lift/cascade/dissolve/
  shudder), e após ~0.8s o indicador **assenta num `breathe` contínuo na cor da
  operação** — vivo pela vida inteira da toast, em lockstep com o shimmer da borda.
  Mensagens simples (sem contexto) vão direto ao breathe em ice-blue. Como o
  breathe não tem `accentOverride`, ele herda o accent semântico da toast, então
  indicador, shimmer e glow respiram **o mesmo tom** (§5.1). Fonte:
  `ToastView.swift`.
- **2026-06-13 — Surgimento faseado do indicador na toast.** O `onAppear` da toast
  disparava o verbo no instante da inserção, então ele rodava **durante** o
  slide-in da pill (mascarado pelo fade) e já tinha acabado quando ela assentava —
  lia como "indicador já vem parado". Correção via revelação faseada (§6): durante
  o slide o indicador fica apagado/encolhido (`dotAppeared = false`); ~0.12s depois,
  conforme a pill assenta, ele **floresce** (`scale 0.5→1` + opacity, spring
  response 0.36); só então (~0.30s) o verbo anuncia. A luz "acorda com" a toast.
  Fonte: `ToastView.swift`.
- **2026-06-13 — §8 consolidado.** Referência do `DotMatrixIndicator` reunida numa
  seção própria (estado atual autoritativo), já que as entradas acima são
  cronológicas e parcialmente superseded (3×3, `boolFrames`, `pixelSize` mudaram).
  Changelog renumerado para §9.
- **2026-06-13 — DotMatrix: malha quadrada → íris radial (padrão do app).** A
  geometria saiu da grade quadrada para uma **íris concêntrica** de pontos
  (`DotMatrixLayout.standardIris`: centro + 6 + 12 = 19). Motivação: estética mais
  orgânica e fiel ao espírito "tela de luz" — e metade do vocabulário (orbit,
  converge, bloom, breathe) já era radial por natureza, então fica *melhor* na
  íris. A sacada arquitetural: o contrato data-driven (frame = `[Double]`, engine,
  spring por pixel) é **agnóstico ao layout** — só a posição dos pontos e o cálculo
  de intensidade por verbo estavam acoplados ao quadrado. Trocou-se o índice
  row-major por uma lista ordenada de `DotMatrixDot` (`point`/`ring`/`angle`); cada
  verbo virou `…Radial`, lendo `ring(of:)`/`outerRingIndices` em vez de
  `ring(idx,n)`/`perimeter(n)`. Os verbos lineares (lift/cascade/dissolve)
  sobrevivem porque cada ponto tem `point.y` real → "subir/descer" é uma **banda de
  brilho varrendo y**, não um índice de linha. O `shudder` (sem diagonal numa
  íris) virou **jolt radial**: anéis flamejam pra fora + jitter + flash vermelho +
  colapso ao centro. A íris é o **default** (`layout: .standardIris`); a malha 5×5
  sobrevive como fallback legado (`layout: nil`). Consumidores (`ToastView`,
  `BrowserToolbar`) inalterados na API — só o copy-path trocou os customs para
  `dualOrbitRadial`/`dualOrbitDoneRadial`. Fonte: `DotMatrixIndicator.swift`,
  `BrowserToolbar.swift`.
```
