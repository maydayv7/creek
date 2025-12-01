import json
import math
import numpy as np
from collections import defaultdict
from typing import List, Dict, Tuple, Any
from sklearn.cluster import KMeans

# ==========================================
#  HYPERPARAMETERS
# ==========================================
RANK_DECAY_FACTOR = 0.85       # Priority drops for lower-ranked tags
MIN_CONSENSUS_THRESHOLD = 0.05 # Filter out noise
PALETTE_SIZE = 5               # Number of colors in final palette

# ==========================================
#  HELPER: COLOR MATH
# ==========================================
def hex_to_rgb(hex_str: str) -> List[int]:
    """Converts '#FF5733' to [255, 87, 51] for math operations."""
    try:
        hex_str = hex_str.strip().lstrip('#')
        if len(hex_str) != 6: return [0, 0, 0]
        return [int(hex_str[i:i+2], 16) for i in (0, 2, 4)]
    except:
        return [0, 0, 0]

def rgb_to_hex(rgb: List[int]) -> str:
    """Converts [255, 87, 51] back to '#FF5733'."""
    return '#{:02x}{:02x}{:02x}'.format(int(rgb[0]), int(rgb[1]), int(rgb[2]))

# ==========================================
#  KNOWLEDGE BASE: FONTS
# ==========================================
class FontClusterEngine:
    def __init__(self):
        self.full_font_map = {
            "abeezee": "Sans Serif (Generic)", "abel": "Condensed Sans", "abhayalibre": "Serif (Generic)",
            "abrilfatface": "Modern Serif", "abyssinicasil": "Serif (Generic)", "aclonica": "Display/Other",
            "acme": "Display/Other", "actor": "Sans Serif (Generic)", "adamina": "Serif (Generic)",
            "adventpro": "Display/Other", "aguafinascript": "Script/Handwritten", "akronim": "Display/Other",
            "aladin": "Display/Other", "aldrich": "Display/Other", "alef": "Sans Serif (Generic)",
            "alegreya": "Old Style Serif", "alegreyasans": "Humanist Sans", "alegreyasanssc": "Sans Serif (Generic)",
            "alegreyasc": "Old Style Serif", "alexbrush": "Script/Handwritten", "alfaslabone": "Slab Serif",
            "alice": "Serif (Generic)", "alike": "Serif (Generic)", "alikeangular": "Serif (Generic)",
            "allan": "Display/Other", "allerta": "Sans Serif (Generic)", "allertastencil": "Display/Other",
            "allura": "Script/Handwritten", "almendra": "Display/Other", "almendradisplay": "Display/Other",
            "almendrasc": "Display/Other", "amarante": "Display/Other", "amaranth": "Display/Other",
            "amaticasc": "Script/Handwritten", "amaticsc": "Script/Handwritten", "amethysta": "Serif (Generic)",
            "amiko": "Sans Serif (Generic)", "amiri": "Serif (Generic)", "amita": "Script/Handwritten",
            "anaheim": "Sans Serif (Generic)", "andada": "Serif (Generic)", "andadasc": "Serif (Generic)",
            "andika": "Sans Serif (Generic)", "annieuseyourtelescope": "Script/Handwritten", "anonymouspro": "Monospace",
            "antic": "Sans Serif (Generic)", "anticdidone": "Serif (Generic)", "anticslab": "Slab Serif",
            "anton": "Grotesque Sans", "antonio": "Sans Serif (Generic)", "arapey": "Serif (Generic)",
            "arbutus": "Display/Other", "arbutusslab": "Slab Serif", "architectsdaughter": "Script/Handwritten",
            "archivo": "Grotesque Sans", "archivoblack": "Grotesque Sans", "archivonarrow": "Condensed Sans",
            "archivovfbeta": "Grotesque Sans", "arefruqaa": "Serif (Generic)", "arimamadurai": "Display/Other",
            "arimo": "Neo-Grotesque Sans", "arizonia": "Script/Handwritten", "armata": "Sans Serif (Generic)",
            "arsenal": "Sans Serif (Generic)", "artifika": "Serif (Generic)", "arvo": "Slab Serif",
            "arya": "Sans Serif (Generic)", "asap": "Rounded Sans", "asapcondensed": "Condensed Sans",
            "asapvfbeta": "Rounded Sans", "asar": "Serif (Generic)", "asset": "Display/Other",
            "assistant": "Sans Serif (Generic)", "astloch": "Display/Other", "asul": "Sans Serif (Generic)",
            "athiti": "Sans Serif (Generic)", "atma": "Display/Other", "atomicage": "Display/Other",
            "aubrey": "Display/Other", "audiowide": "Display/Other", "autourone": "Display/Other",
            "average": "Serif (Generic)", "averagesans": "Sans Serif (Generic)", "averiagruesalibre": "Display/Other",
            "averialibre": "Display/Other", "averiasanslibre": "Sans Serif (Generic)", "averiaseriflibre": "Serif (Generic)",
            "badscript": "Script/Handwritten", "bahiana": "Display/Other", "baloo": "Display/Other",
            "baloobhai": "Display/Other", "baloobhaijaan": "Display/Other", "baloobhaina": "Display/Other",
            "baloochettan": "Display/Other", "balooda": "Display/Other", "baloopaaji": "Display/Other",
            "balootamma": "Display/Other", "balootammudu": "Display/Other", "baloothambi": "Display/Other",
            "balthazar": "Serif (Generic)", "bangers": "Display", "barlow": "Grotesque Sans",
            "barlowcondensed": "Condensed Sans", "barlowsemicondensed": "Condensed Sans", "barrio": "Display/Other",
            "basic": "Sans Serif (Generic)", "baumans": "Display/Other", "belgrano": "Serif (Generic)",
            "bellefair": "Serif (Generic)", "belleza": "Sans Serif (Generic)", "benchnine": "Sans Serif (Generic)",
            "bentham": "Serif (Generic)", "berkshireswash": "Script/Handwritten", "bevan": "Slab Serif",
            "bhavuka": "Display/Other", "bigelowrules": "Display/Other", "bigshotone": "Display/Other",
            "bilbo": "Script/Handwritten", "bilboswashcaps": "Script/Handwritten", "biorhyme": "Slab Serif",
            "biorhymeexpanded": "Slab Serif", "biryani": "Sans Serif (Generic)", "bitter": "Slab Serif",
            "blackandwhitepicture": "Display/Other", "blackhansans": "Sans Serif (Generic)", "blackopsone": "Display/Other",
            "bonbon": "Display/Other", "boogaloo": "Display/Other", "bowlbyone": "Display/Other",
            "bowlbyonesc": "Display/Other", "brawler": "Serif (Generic)", "breeserif": "Slab Serif",
            "brunoace": "Display/Other", "brunoacesc": "Display/Other", "bubblegumsans": "Display/Other",
            "bubblerone": "Display/Other", "buenard": "Serif (Generic)", "bungee": "Display/Other",
            "bungeehairline": "Display/Other", "bungeeinline": "Display/Other", "bungeeoutline": "Display/Other",
            "bungeeshade": "Display/Other", "butcherman": "Display/Other", "butchermancaps": "Display/Other",
            "butterflykids": "Script/Handwritten", "cabin": "Humanist Sans", "cabincondensed": "Condensed Sans",
            "cabinsketch": "Display/Other", "cabinvfbeta": "Humanist Sans", "caesardressing": "Display/Other",
            "cagliostro": "Sans Serif (Generic)", "cairo": "Grotesque Sans", "calligraffitti": "Script/Handwritten",
            "cambay": "Sans Serif (Generic)", "cambo": "Serif (Generic)", "cantarell": "Sans Serif (Generic)",
            "cantataone": "Serif (Generic)", "cantoraone": "Sans Serif (Generic)", "capriola": "Sans Serif (Generic)",
            "cardo": "Serif (Generic)", "carme": "Sans Serif (Generic)", "carroisgothic": "Sans Serif (Generic)",
            "carroisgothicsc": "Sans Serif (Generic)", "catamaran": "Sans Serif", "caudex": "Serif (Generic)",
            "caveat": "Script/Handwritten", "caveatbrush": "Script/Handwritten", "cevicheone": "Display/Other",
            "changa": "Sans Serif (Generic)", "changaone": "Display/Other", "chango": "Display/Other",
            "chathura": "Sans Serif (Generic)", "chauphilomeneone": "Display/Other", "chelaone": "Display/Other",
            "chelseamarket": "Display/Other", "cherrycreamsoda": "Display/Other", "cherryswash": "Display/Other",
            "chewy": "Display", "chicle": "Display/Other", "chivo": "Grotesque Sans",
            "chonburi": "Display/Other", "cinzel": "Serif", "cinzeldecorative": "Display/Other",
            "clickerscript": "Script/Handwritten", "coda": "Display/Other", "codystar": "Display/Other",
            "coiny": "Display/Other", "combo": "Display/Other", "comfortaa": "Rounded Sans",
            "comingsoon": "Script/Handwritten", "concertone": "Display/Other", "condiment": "Script/Handwritten",
            "contrailone": "Display/Other", "convergence": "Sans Serif (Generic)", "cookie": "Script",
            "copse": "Slab Serif", "cormorant": "Old Style Serif", "cormorantgaramond": "Old Style Serif",
            "cormorantinfant": "Old Style Serif", "cormorantsc": "Old Style Serif", "cormorantunicase": "Old Style Serif",
            "cormorantupright": "Old Style Serif", "courgette": "Script", "cousine": "Monospace",
            "coustard": "Slab Serif", "craftygirls": "Script/Handwritten", "creepster": "Display/Other",
            "creepstercaps": "Display/Other", "creteround": "Slab Serif", "crimsontext": "Old Style Serif",
            "croissantone": "Display/Other", "crushed": "Display/Other", "cuprum": "Sans Serif",
            "cutefont": "Display/Other", "cutive": "Serif (Generic)", "cutivemono": "Monospace",
            "damion": "Script/Handwritten", "dancingscript": "Script/Handwritten", "daysone": "Display/Other",
            "decovaralpha": "Display/Other", "dekko": "Script/Handwritten", "delius": "Script/Handwritten",
            "deliusswashcaps": "Script/Handwritten", "deliusunicase": "Script/Handwritten", "dellarespira": "Serif (Generic)",
            "denkone": "Display/Other", "devonshire": "Script/Handwritten", "dhurjati": "Display/Other",
            "dhyana": "Display/Other", "didactgothic": "Sans Serif (Generic)", "digitalnumbers": "Display/Other",
            "diplomata": "Display/Other", "diplomatasc": "Display/Other", "dohyeon": "Sans Serif (Generic)",
            "dokdo": "Script/Handwritten", "domine": "Serif", "donegalone": "Display/Other",
            "doppioone": "Sans Serif (Generic)", "dorsa": "Display/Other", "dosis": "Rounded Sans",
            "drsugiyama": "Script/Handwritten", "durusans": "Sans Serif (Generic)", "dynalight": "Script/Handwritten",
            "eaglelake": "Script/Handwritten", "eastseadokdo": "Script/Handwritten", "eater": "Display/Other",
            "eatercaps": "Display/Other", "ebgaramond": "Old Style Serif", "economica": "Sans Serif (Generic)",
            "eczar": "Display/Other", "ekmukta": "Sans Serif (Generic)", "electrolize": "Display/Other",
            "elmessiri": "Sans Serif (Generic)", "elsie": "Display/Other", "elsieswashcaps": "Display/Other",
            "emblemaone": "Display/Other", "emilyscandy": "Display/Other", "encodesans": "Sans Serif",
            "encodesanscondensed": "Condensed Sans", "encodesansexpanded": "Sans Serif (Generic)", "encodesanssemicondensed": "Condensed Sans",
            "encodesanssemiexpanded": "Sans Serif (Generic)", "engagement": "Script/Handwritten", "englebert": "Display/Other",
            "enriqueta": "Slab Serif", "ericaone": "Display/Other", "esteban": "Serif (Generic)",
            "euphoriascript": "Script/Handwritten", "ewert": "Display/Other", "exo": "Geometric Sans",
            "exo2": "Geometric Sans", "expletussans": "Display/Other", "fanwoodtext": "Serif (Generic)",
            "farsan": "Display/Other", "fascinate": "Display/Other", "fascinateinline": "Display/Other",
            "fasterone": "Display/Other", "fasthand": "Script/Handwritten", "faunaone": "Serif (Generic)",
            "faustina": "Serif (Generic)", "faustinavfbeta": "Serif (Generic)", "federant": "Display/Other",
            "federo": "Display/Other", "felipa": "Script/Handwritten", "fenix": "Serif (Generic)",
            "fingerpaint": "Display/Other", "firasans": "Humanist Sans", "firasanscondensed": "Condensed Sans",
            "firasansextracondensed": "Condensed Sans", "fjallaone": "Grotesque Sans", "fjordone": "Serif (Generic)",
            "flamenco": "Display/Other", "flavors": "Display/Other", "fondamento": "Script/Handwritten",
            "fontdinerswanky": "Display/Other", "forum": "Display/Other", "francoisone": "Sans Serif",
            "frankruhllibre": "Serif (Generic)", "freckleface": "Display/Other", "frederickathegreat": "Display/Other",
            "fredokaone": "Rounded Display", "fresca": "Sans Serif (Generic)", "frijole": "Display/Other",
            "fruktur": "Display/Other", "fugazone": "Display/Other", "gabriela": "Serif (Generic)",
            "gaegu": "Script/Handwritten", "gafata": "Sans Serif (Generic)", "galada": "Display/Other",
            "galdeano": "Sans Serif (Generic)", "galindo": "Display/Other", "gamjaflower": "Script/Handwritten",
            "gemunulibre": "Sans Serif (Generic)", "genbasb": "Serif (Generic)", "genbasbi": "Serif (Generic)",
            "genbkbasb": "Serif (Generic)", "genbkbasbi": "Serif (Generic)", "geo": "Display/Other",
            "geostar": "Display/Other", "geostarfill": "Display/Other", "germaniaone": "Display/Other",
            "gfsdidot": "Serif (Generic)", "gfsneohellenic": "Sans Serif (Generic)", "gfsneohellenicbold": "Sans Serif (Generic)",
            "gfsneohellenicbolditalic": "Sans Serif (Generic)", "gidugu": "Display/Other", "gildadisplay": "Serif (Generic)",
            "glassantiqua": "Display/Other", "glegoo": "Slab Serif", "gochihand": "Script/Handwritten",
            "gorditas": "Display/Other", "gothica1": "Sans Serif (Generic)", "graduate": "Display/Other",
            "grandhotel": "Script/Handwritten", "greatvibes": "Script", "griffy": "Display/Other",
            "gruppo": "Display/Other", "gudea": "Sans Serif (Generic)", "gugi": "Display/Other",
            "gurajada": "Display/Other", "habibi": "Serif (Generic)", "halant": "Serif (Generic)",
            "hammersmithone": "Sans Serif (Generic)", "hanalei": "Display/Other", "hanaleifill": "Display/Other",
            "handlee": "Script/Handwritten", "hannari": "Display/Other", "hanuman": "Serif (Generic)",
            "happymonkey": "Display/Other", "harmattan": "Sans Serif (Generic)", "headlandone": "Serif (Generic)",
            "heebo": "Sans Serif", "hennypenny": "Display/Other", "hermeneusone": "Sans Serif (Generic)",
            "herrvonmuellerhoff": "Script/Handwritten", "himelody": "Script/Handwritten", "hind": "Humanist Sans",
            "hindcolombo": "Sans Serif (Generic)", "hindguntur": "Sans Serif (Generic)", "hindjalandhar": "Sans Serif (Generic)",
            "hindkochi": "Sans Serif (Generic)", "hindmadurai": "Sans Serif (Generic)", "hindmysuru": "Sans Serif (Generic)",
            "hindsiliguri": "Sans Serif (Generic)", "hindvadodara": "Sans Serif (Generic)", "homemadeapple": "Script/Handwritten",
            "homenaje": "Sans Serif (Generic)", "ibmplexmono": "Monospace", "ibmplexsans": "Neo-Grotesque Sans",
            "ibmplexsanscondensed": "Condensed Sans", "ibmplexserif": "Transitional Serif", "iceberg": "Display/Other",
            "iceland": "Display/Other", "imprima": "Sans Serif (Generic)", "inconsolata": "Monospace",
            "inder": "Sans Serif (Generic)", "indieflower": "Handwritten", "inika": "Serif (Generic)",
            "inknutantiqua": "Serif (Generic)", "irishgrover": "Display/Other", "istokweb": "Sans Serif (Generic)",
            "italiana": "Serif (Generic)", "italianno": "Script/Handwritten", "itim": "Script/Handwritten",
            "jacquesfrancois": "Display/Other", "jacquesfrancoisshadow": "Display/Other", "jaldi": "Sans Serif (Generic)",
            "jejugothic": "Sans Serif (Generic)", "jejuhallasan": "Display/Other", "jejumyeongjo": "Serif (Generic)",
            "jimnightshade": "Display/Other", "jockeyone": "Display/Other", "jollylodger": "Display/Other",
            "jomhuria": "Display/Other", "josefinsans": "Geometric Sans", "josefinslab": "Slab Serif",
            "jotione": "Display/Other", "jua": "Sans Serif (Generic)", "judson": "Serif (Generic)",
            "julee": "Script/Handwritten", "juliussansone": "Sans Serif (Generic)", "junge": "Serif (Generic)",
            "jura": "Sans Serif (Generic)", "justanotherhand": "Script/Handwritten", "kadwa": "Serif (Generic)",
            "kalam": "Handwritten", "kameron": "Serif (Generic)", "kanit": "Sans Serif",
            "kantumruy": "Sans Serif (Generic)", "karla": "Sans Serif (Generic)", "karlatamilinclined": "Sans Serif (Generic)",
            "karlatamilupright": "Sans Serif (Generic)", "karma": "Serif (Generic)", "katibeh": "Display/Other",
            "kaushanscript": "Script", "kavivanar": "Script/Handwritten", "kavoon": "Display/Other",
            "kdamthmor": "Display/Other", "keaniaone": "Display/Other", "kellyslab": "Display/Other",
            "kenia": "Display/Other", "khand": "Sans Serif", "khula": "Sans Serif (Generic)",
            "khyay": "Display/Other", "kiranghaerang": "Display/Other", "kiteone": "Sans Serif (Generic)",
            "knewave": "Display/Other", "kokoro": "Display/Other", "kopubbatang": "Serif (Generic)",
            "kottaone": "Serif (Generic)", "kranky": "Display/Other", "kreon": "Slab Serif",
            "kristi": "Script/Handwritten", "kronaone": "Sans Serif (Generic)", "kurale": "Serif (Generic)",
            "laila": "Serif (Generic)", "lakkireddy": "Display/Other", "lalezar": "Display/Other",
            "lancelot": "Display/Other", "laomuangdon": "Display/Other", "laomuangkhong": "Display/Other",
            "laosanspro": "Sans Serif (Generic)", "lato": "Humanist Sans", "leckerlione": "Display/Other",
            "ledger": "Serif (Generic)", "lekton": "Monospace", "lemon": "Display/Other",
            "lemonada": "Display/Other", "lemonadavfbeta": "Display/Other", "librebaskerville": "Serif (Generic)",
            "librecaslontext": "Serif (Generic)", "librefranklin": "Neo-Grotesque Sans", "lifesavers": "Display/Other",
            "lilitaone": "Display/Other", "lilyscriptone": "Display/Other", "limelight": "Display/Other",
            "lindenhill": "Serif (Generic)", "lobster": "Script", "lobstertwo": "Script/Handwritten",
            "londrinaoutline": "Display/Other", "londrinashadow": "Display/Other", "londrinasketch": "Display/Other",
            "londrinasolid": "Display/Other", "lora": "Old Style Serif", "loversquarrel": "Script/Handwritten",
            "loveyalikeasister": "Script/Handwritten", "luckiestguy": "Display/Other", "lusitana": "Serif (Generic)",
            "lustria": "Serif (Generic)", "macondo": "Display/Other", "macondoswashcaps": "Display/Other",
            "mada": "Sans Serif (Generic)", "magra": "Sans Serif (Generic)", "maidenorange": "Display/Other",
            "maitree": "Serif (Generic)", "mako": "Sans Serif (Generic)", "mallanna": "Display/Other",
            "mandali": "Sans Serif (Generic)", "manuale": "Serif (Generic)", "marcellus": "Serif (Generic)",
            "marcellussc": "Serif (Generic)", "marckscript": "Script/Handwritten", "margarine": "Display/Other",
            "markazitext": "Serif (Generic)", "markoone": "Serif (Generic)", "marmelad": "Sans Serif (Generic)",
            "martel": "Serif (Generic)", "martelsans": "Sans Serif (Generic)", "marvel": "Sans Serif (Generic)",
            "mate": "Serif (Generic)", "matesc": "Serif (Generic)", "mavenpro": "Geometric Sans",
            "mavenprovfbeta": "Geometric Sans", "mclaren": "Display/Other", "medulaone": "Display/Other",
            "meerainimai": "Display/Other", "meiescript": "Script/Handwritten", "mergeone": "Sans Serif (Generic)",
            "merienda": "Display/Other", "meriendaone": "Display/Other", "merriweather": "Transitional Serif",
            "merriweathersans": "Humanist Sans", "mervalescript": "Script/Handwritten", "metalmania": "Display/Other",
            "metamorphous": "Display/Other", "metrophobic": "Sans Serif (Generic)", "miama": "Script/Handwritten",
            "milonga": "Display/Other", "miltonian": "Display/Other", "miltoniantattoo": "Display/Other",
            "mina": "Sans Serif (Generic)", "miniver": "Display/Other", "miriamlibre": "Sans Serif (Generic)",
            "mirza": "Display/Other", "missfajardose": "Script/Handwritten", "mitr": "Sans Serif (Generic)",
            "modak": "Display/Other", "modernantiqua": "Serif (Generic)", "mogra": "Display/Other",
            "molengo": "Sans Serif (Generic)", "molle": "Display/Other", "monda": "Sans Serif (Generic)",
            "monoton": "Display/Other", "monsieurladoulaise": "Script/Handwritten", "montaga": "Serif (Generic)",
            "montez": "Script/Handwritten", "montserrat": "Geometric Sans", "montserratalternates": "Geometric Sans",
            "montserratsubrayada": "Geometric Sans", "mountainsofchristmas": "Display/Other", "mousememoirs": "Display/Other",
            "mplus1p": "Rounded Sans", "mrbedfort": "Script/Handwritten", "mrdafoe": "Script/Handwritten",
            "mrdehaviland": "Script/Handwritten", "mrssaintdelafield": "Script/Handwritten", "mrssheppards": "Script/Handwritten",
            "mukta": "Sans Serif", "muktamahee": "Sans Serif (Generic)", "muktamalar": "Sans Serif (Generic)",
            "muktavaani": "Sans Serif (Generic)", "muli": "Humanist Sans", "myanmarsanspro": "Sans Serif (Generic)",
            "mysteryquest": "Display/Other", "nanumbrushscript": "Script/Handwritten", "nanumgothic": "Sans Serif (Generic)",
            "nanumgothiccoding": "Monospace", "nanummyeongjo": "Serif (Generic)", "nanumpenscript": "Script/Handwritten",
            "nats": "Display/Other", "neuton": "Serif (Generic)", "newrocker": "Display/Other",
            "newscycle": "Sans Serif (Generic)", "nicomoji": "Display/Other", "niconne": "Script/Handwritten",
            "nikukyu": "Display/Other", "nixieone": "Display/Other", "nobile": "Sans Serif (Generic)",
            "nokora": "Sans Serif (Generic)", "norican": "Script/Handwritten", "nosifer": "Display/Other",
            "nosifercaps": "Display/Other", "notable": "Display/Other", "noticiatext": "Serif (Generic)",
            "notosans": "Humanist Sans", "notosanstamil": "Humanist Sans", "notoserif": "Transitional Serif",
            "novascript": "Display/Other", "ntr": "Sans Serif (Generic)", "numans": "Sans Serif (Generic)",
            "nunito": "Rounded Sans", "nunitosans": "Rounded Sans", "offside": "Display/Other",
            "oldenburg": "Display/Other", "oldstandard": "Serif (Generic)", "oleoscript": "Script/Handwritten",
            "oleoscriptswashcaps": "Script/Handwritten", "opensans": "Humanist Sans", "opensanscondensed": "Condensed Sans",
            "opensanshebrew": "Humanist Sans", "opensanshebrewcondensed": "Condensed Sans", "oranienbaum": "Serif (Generic)",
            "orbitron": "Display/Other", "oregano": "Script/Handwritten", "orienta": "Sans Serif (Generic)",
            "originalsurfer": "Display/Other", "oswald": "Grotesque Sans", "overlock": "Display/Other",
            "overlocksc": "Display/Other", "overpass": "Sans Serif (Generic)", "overpassmono": "Monospace",
            "ovo": "Serif (Generic)", "oxygen": "Geometric Sans", "oxygenmono": "Monospace",
            "pacifico": "Script", "palanquin": "Sans Serif (Generic)", "palanquindark": "Sans Serif (Generic)",
            "pangolin": "Script/Handwritten", "paprika": "Display/Other", "parisienne": "Script/Handwritten",
            "passeroone": "Display/Other", "passionone": "Display", "pathwaygothicone": "Condensed Sans",
            "patrickhand": "Script/Handwritten", "patrickhandsc": "Script/Handwritten", "pattaya": "Display/Other",
            "patuaone": "Slab Serif", "pavanam": "Sans Serif (Generic)", "paytoneone": "Sans Serif (Generic)",
            "peddana": "Serif (Generic)", "peralta": "Display/Other", "permanentmarker": "Handwritten",
            "petitformalscript": "Script/Handwritten", "petrona": "Serif (Generic)", "philosopher": "Sans Serif (Generic)",
            "piedra": "Display/Other", "pinyonscript": "Script/Handwritten", "pirataone": "Display/Other",
            "plaster": "Display/Other", "play": "Sans Serif (Generic)", "playball": "Script/Handwritten",
            "playfairdisplay": "Modern Serif", "playfairdisplaysc": "Modern Serif", "podkova": "Slab Serif",
            "podkovavfbeta": "Slab Serif", "poetsenone": "Display/Other", "poiretone": "Display/Other",
            "poly": "Serif (Generic)", "pompiere": "Display/Other", "ponnala": "Display/Other",
            "pontanosans": "Sans Serif (Generic)", "poorstory": "Display/Other", "poppins": "Geometric Sans",
            "portersansblock": "Display/Other", "portlligatsans": "Display/Other", "portlligatslab": "Display/Other",
            "postnobillscolombo": "Display/Other", "postnobillsjaffna": "Display/Other", "pragatinarrow": "Condensed Sans",
            "prata": "Serif (Generic)", "pressstart2p": "Display/Other", "pridi": "Serif (Generic)",
            "princesssofia": "Script/Handwritten", "prociono": "Serif (Generic)", "prompt": "Sans Serif",
            "prostoone": "Display/Other", "prozalibre": "Sans Serif (Generic)", "pt_sans": "Humanist Sans",
            "pt_serif": "Transitional Serif", "puritan": "Sans Serif (Generic)", "purplepurse": "Display/Other",
            "questrial": "Geometric Sans", "qwigley": "Script/Handwritten"
        }

    def get_cluster(self, raw_name: str) -> str:
        clean = raw_name.lower().split('-')[0].strip()
        if clean in self.full_font_map:
            return self.full_font_map[clean]
        return "Unknown/Other"

# ==========================================
#  UNIFIED CONSENSUS ENGINE
# ==========================================
class UnifiedStyleEngine:
    def __init__(self):
        self.feature_registry = defaultdict(lambda: defaultdict(list))
        self.font_engine = FontClusterEngine()
        self.font_family_scores = defaultdict(float)
        self.font_individual_scores = defaultdict(float)
        self.font_members = defaultdict(list)
        self.color_pool = []
        self.doc_counter = 0

        self.aliases = {
            "Colour Palette": "Color Palette",
            "Texture": "Background/Texture", 
            "Era": "Era/Cultural Reference",
            "Font": "Typography",
            "Fonts": "Typography",
            "Text": "Typography",
            "Layout": "Composition"
        }

    def ingest_data(self, data: Dict):
        """
        Parses the JSON structure from the app
        Handles: { "success": true, "data": { "results": { ... } } }
        """
        try:
            self.doc_counter += 1

            # 1. Unwrapping logic to find "results"
            source_data = {}
            if "data" in data and isinstance(data["data"], dict):
                # Check for nested "results" inside "data"
                if "results" in data["data"]:
                    source_data = data["data"]["results"]
                else:
                    source_data = data["data"]
            elif "results" in data:
                source_data = data["results"]
            else:
                source_data = data

            # 2. Iterate through categories
            for category, payload in source_data.items():
                if category in ["filename", "meta"]: continue

                # Map "Font" -> "Typography", etc.
                std_category = self.aliases.get(category, category)

                # PATH A: COLOR PALETTE
                # NOTE: We intentionally SKIP processing 'scores' (moods) here
                if std_category == "Color Palette":
                    if isinstance(payload, dict):
                        # Extract "palette" list (Actual Hex Codes)
                        if "palette" in payload and isinstance(payload["palette"], list):
                            for hex_code in payload["palette"]:
                                if isinstance(hex_code, str) and hex_code.startswith('#'):
                                    self.color_pool.append(hex_to_rgb(hex_code))
                    # Fallback: if payload is just a list of hex strings
                    elif isinstance(payload, list):
                        for item in payload:
                            if isinstance(item, str) and item.startswith('#'):
                                self.color_pool.append(hex_to_rgb(item))

                # PATH B: TYPOGRAPHY
                elif std_category == "Typography":
                    if isinstance(payload, dict) and "scores" in payload: 
                        payload = payload["scores"]
                    vectors = self._normalize(payload)

                    for rank, (font_name, score) in enumerate(vectors):
                        # Skip "No Text Detected"
                        if "no text" in font_name.lower(): continue

                        weight = math.pow(RANK_DECAY_FACTOR, rank) * score
                        cluster = self.font_engine.get_cluster(font_name)

                        self.font_family_scores[cluster] += weight
                        self.font_individual_scores[font_name] += weight
                        if font_name not in self.font_members[cluster]:
                            self.font_members[cluster].append(font_name)

                # PATH C: OTHER TAGS
                else:
                    if isinstance(payload, dict) and "scores" in payload: 
                        payload = payload["scores"]
                    vectors = self._normalize(payload)

                    for rank, (label, score) in enumerate(vectors):
                        self.feature_registry[std_category][label].append({
                            "raw_score": score,
                            "rank": rank
                        })

        except Exception as e:
            print(f"Warning during ingestion: {e}")

    def _normalize(self, payload) -> List[Tuple[str, float]]:
        """
        Robustly converts inputs to [(label, score), ...]
        Handles mixed types and weird nesting to prevent crashes.
        """
        if isinstance(payload, dict):
            clean_items = []
            for k, v in payload.items():
                # Only accept numeric values as scores
                if isinstance(v, (int, float)):
                    clean_items.append((k, float(v)))
            return sorted(clean_items, key=lambda x: x[1], reverse=True)

        if isinstance(payload, list):
            res = []
            for item in payload:
                if isinstance(item, dict):
                    try:
                        score = float(item.get('score', 0.9))
                    except (ValueError, TypeError):
                        score = 0.0
                    
                    # Try 'label' or 'tag'
                    label = item.get('label', item.get('tag', 'unknown'))
                    if not isinstance(label, str): label = str(label)
                    
                    res.append((label, score))
                elif isinstance(item, str):
                    res.append((item, 1.0))
            return res
        return []

    def compute_final_stylesheet(self) -> Dict:
        final_json = {"results": {}}

        # 1. Process Standard Tags
        for category, tags_map in self.feature_registry.items():
            candidates = []
            for tag, occurrences in tags_map.items():
                # Weighted Sum
                w_sum = sum(obs['raw_score'] * math.pow(RANK_DECAY_FACTOR, obs['rank']) for obs in occurrences)
                score = w_sum / max(1, self.doc_counter)

                if score > MIN_CONSENSUS_THRESHOLD:
                    candidates.append({"label": tag, "score": round(score, 2)})

            candidates.sort(key=lambda x: x['score'], reverse=True)
            if candidates: final_json["results"][category] = candidates[:5]

        # 2. Process Typography
        if self.font_family_scores:
            best_fam, _ = sorted(self.font_family_scores.items(), key=lambda x: x[1], reverse=True)[0]
            members = self.font_members[best_fam]
            members.sort(key=lambda x: self.font_individual_scores[x], reverse=True)

            typo_output = []
            for font in members[:5]:
                score = self.font_individual_scores[font] / max(1, self.doc_counter)
                typo_output.append({"label": font, "score": round(score, 2)})

            final_json["results"]["Typography"] = typo_output
            final_json["results"]["Typography_Family"] = best_fam

        # 3. Process Color Palette
        if len(self.color_pool) > 0:
            try:
                # If we have very few colors, just use all of them
                k_clusters = min(len(self.color_pool), PALETTE_SIZE)

                # FIX: n_init='auto' crashes on older sklearn. Used n_init=1.
                kmeans = KMeans(n_clusters=k_clusters, n_init=1, random_state=42)
                kmeans.fit(self.color_pool)
                centers = sorted(kmeans.cluster_centers_.astype(int).tolist(), key=sum)

                palette_output = []
                for i, rgb in enumerate(centers):
                    palette_output.append({
                        "label": rgb_to_hex(rgb),
                        "score": round(1.0 - (i * 0.1), 2)
                    })
                final_json["results"]["Color Palette"] = palette_output
            except Exception as e:
                print(f"Color clustering failed: {e}")

        final_json["results"]["meta"] = {"source_files": self.doc_counter}
        return final_json

# ==========================================
#  ENTRY POINT
# ==========================================
def generate_stylesheet(json_strings_list: Any) -> str:
    """
    Entry point
    Accepts a Java ArrayList of JSON strings.
    """
    engine = UnifiedStyleEngine()

    try:
        count = json_strings_list.size()
        for i in range(count):
            json_str = json_strings_list.get(i)
            if not json_str: continue
            try:
                data = json.loads(json_str)
                engine.ingest_data(data)
            except Exception as e:
                print(f"Error parsing JSON chunk at index {i}: {e}")
                continue

    except AttributeError:
        # Fallback for standard Python list (For testing)
        for json_str in json_strings_list:
            if not json_str: continue
            try:
                data = json.loads(json_str)
                engine.ingest_data(data)
            except Exception as e:
                print(f"Error parsing JSON chunk: {e}")
                continue

    final_output = engine.compute_final_stylesheet()
    return json.dumps(final_output)
