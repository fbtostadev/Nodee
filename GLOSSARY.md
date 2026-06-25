# Glossário do Nodee

> Termos de produto memoráveis. Só o que aparece em copy, marketing, onboarding
> ou conversa entre time. Componentes internos sem marca ficam com seus nomes
> técnicos normais — não precisam de fantasia.

---

## Filosofia

O Nodee vive no Notch — ao lado da câmera, o olho do Mac. Essa posição
inspira a identidade visual do produto: luz, foco e visão. Mas nem tudo
precisa de um nome temático. **Só brande o que o usuário vai lembrar.**

---

## Termos de Produto

### **Aperture** (A Abertura)
O painel principal. Quando o Nodee abre, você "abre a Aperture". Quando
fecha, a Aperture se recolhe de volta ao Notch. É o nome do estado aberto
do app — o espaço de trabalho inteiro.
- Refs: [PanelRootView.swift](Nodee/App/PanelRootView.swift), [NotchPanelController.swift](Nodee/Notch/NotchPanelController.swift), [PanelPresentation.swift](Nodee/Notch/PanelPresentation.swift), [NotchGeometry.swift](Nodee/Notch/NotchGeometry.swift), [NotchShapes.swift](Nodee/Notch/NotchShapes.swift)

### **ViewFinder** (O Visor)
A sidebar de projetos e locais (painel esquerdo). Onde você enquadra qual
projeto está olhando.
- Refs: [SidebarView.swift](Nodee/Sidebar/SidebarView.swift), [SidebarLocation.swift](Nodee/Sidebar/SidebarLocation.swift)

### **The Lens** (A Lente)
O painel de preview (painel direito). Amplia o arquivo selecionado sem
precisar abrir outro app.
- Refs: [PreviewPane.swift](Nodee/Preview/PreviewPane.swift), [PreviewStore.swift](Nodee/Preview/PreviewStore.swift), [QuickLookPreview.swift](Nodee/Preview/QuickLookPreview.swift)

### **The Brow** (A Sobrancelha)
A toolbar fina no topo — back/forward, breadcrumb, ações. Curta, limpa,
funcional.
- Refs: [BrowserToolbar.swift](Nodee/Browser/BrowserToolbar.swift)

### **Action Shelf** (A Prateleira de Ação)
A zona de drop e ações rápidas na base do painel. Onde as coisas "pousam"
para serem organizadas.
- Refs: [GrabberHandle.swift](Nodee/Notch/GrabberHandle.swift), [PaneDivider.swift](Nodee/Support/PaneDivider.swift)

### **Flash Notification**
A notificação transiente que aparece após uma ação (mover, copiar, deletar).
Compacta como uma pílula; expande em hover para mostrar detalhes.
- Refs: [ToastView.swift](Nodee/Support/ToastView.swift), [ToastCenter.swift](Nodee/Support/ToastCenter.swift)

### **Iris**
O indicador radial de status — o pequeno componente de luz com 19 pontos
que reage a cada operação. É a assinatura visual do Nodee: ele não mostra
texto de status, ele *expressa* o estado com luz e movimento.
- Refs: [DotMatrixIndicator.swift](Nodee/Support/DotMatrixIndicator.swift)

### **Scan / Depth**
Os dois modos de visualização de arquivos:
- **Scan** — lista hierárquica (varredura linear).
- **Depth** — colunas Miller (exploração em profundidade).
- Refs: [DisplayMode.swift](Nodee/Browser/DisplayMode.swift), [FileListView.swift](Nodee/Browser/FileListView.swift), [ColumnsView.swift](Nodee/Browser/ColumnsView.swift)

### **Trail**
O breadcrumb de navegação dentro do Brow. Cada segmento é um nível de
pasta já visitado.
- Refs: [BrowserToolbar.swift](Nodee/Browser/BrowserToolbar.swift), [BrowserViewModel.swift](Nodee/Browser/BrowserViewModel.swift)

---

## Paleta Semântica

As cores do Nodee não são decoração — cada uma comunica um tipo de ação:

| Cor | Nome | Uso |
|:---|:---|:---|
| 🔵 | **Ice** | Ação primária, navegação, mover. O tom da casa. |
| 🟡 | **Amber** | Copiar, duplicar. |
| 🔴 | **Red** | Descartar, erro. |
| 🟢 | **Green** | Confirmação transiente (beat final). |

---

## Vocabulário Interno (referência para dev/design)

Estes termos não precisam aparecer em copy ou marketing. São referência
interna para manter a coerência entre código e documentação de design.

### Superfície de vidro (receita padrão)
Toda superfície flutuante no Nodee usa a mesma composição:
material translúcido + véu escuro + borda de luz fixa + shimmer animado +
sombras de glow. Detalhes técnicos no [DSGNConcept.md §3](DSGNConcept.md).
- Refs: [ToastView.swift](Nodee/Support/ToastView.swift), [Theme.swift](Nodee/Support/Theme.swift)

### Shimmer (Aura da borda)
O brilho que percorre a borda das superfícies de vidro:
- **Contínuo** — gira sem parar enquanto o elemento está ativo.
- **Pontual** — uma passagem de confirmação após um evento.
- Refs: [ToastView.swift](Nodee/Support/ToastView.swift), [BrowserToolbar.swift](Nodee/Browser/BrowserToolbar.swift) — detalhes em [DSGNConcept.md §4](DSGNConcept.md)

### Animações da Iris (reflexos)
A Iris se expressa através de animações procedurais por operação:
loading (órbita), sucesso (convergência), mover (ascensão), copiar
(refração), deletar (eclipse), standby (dilatação), erro (aberração),
fixar (flare). Detalhes no [DSGNConcept.md §8](DSGNConcept.md).
- Refs: [DotMatrixIndicator.swift](Nodee/Support/DotMatrixIndicator.swift)

### Escala dos nós (canvas orbital)
Três níveis de detalhe baseados na proximidade ao foco:
- `.dot` — ponto de cor (periferia).
- `.compact` — ícone + nome.
- `.full` — preview completo.
- Refs: [NodeScale.swift](Nodee/Canvas/NodeScale.swift), [FileNodeView.swift](Nodee/Canvas/FileNodeView.swift), [OrbitalLayout.swift](Nodee/Canvas/OrbitalLayout.swift), [CanvasNode.swift](Nodee/Canvas/CanvasNode.swift)

### Gestos
- Hover no Notch → entreabre.
- Dwell 0.5s ou swipe ↓ → abre a Aperture.
- Swipe ↑ ou click no grabber → fecha.
- Drag de arquivo sobre o Notch → abre automaticamente (0.3s).
- Swipe ← → 3 dedos → revela/esconde ViewFinder ou Lens.
- Refs: [NotchGestures.swift](Nodee/Notch/NotchGestures.swift), [DragRevealMonitor.swift](Nodee/Notch/DragRevealMonitor.swift), [GrabberHandle.swift](Nodee/Notch/GrabberHandle.swift), [ZoneGestureMonitor.swift](Nodee/Browser/ZoneGestureMonitor.swift)
