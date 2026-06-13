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
7. **Documente aqui.** Toda variante nova de shimmer/glow/superfície entra no §8
   com sua data e seu propósito. A linguagem só permanece coerente se for escrita.

---

## 8. Evolução / changelog de design

> Registre aqui cada decisão estética relevante — o que mudou, por quê, e onde
> vive no código. Converta datas relativas em absolutas.

- **2026-06-12 — Documento criado.** Formalização da linguagem visual a partir do
  estado atual do MVP. Pilar: **shimmer + glow das ToastNotifications**
  (`ToastView.swift`) como efeito-assinatura, com a variante de **passagem única**
  já replicada no shimmer de copy-path do breadcrumb (`BrowserToolbar.swift`).
  Precedente de glow de estado ativo no canvas arquivado
  (`FileNodeView.orbitalGlow`). Vocabulário semântico de cor (ice-blue / amber /
  red) consolidado neste doc; candidato a migrar para `Theme.swift`.
```
