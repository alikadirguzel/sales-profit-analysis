%% Satış verisi temizleme
% Kolon başlıkları (ilk satır) DEĞİŞTİRİLMEZ.
% Sonuç tablosu: data
% Excel çıktısı (bu klasör): Temizlenmiş_SatışVerisi.xlsx

clc; clear; close all;

%% 0) Ham veriyi oku (başlıklar korunur)
dosyaAdi = 'SatışVerisi.xlsx';
opts = detectImportOptions(dosyaAdi, 'VariableNamingRule', 'preserve');
metinKolonlar = {'Siparis_ID','Tarih','Musteri_ID','Sehir','Bolge','Urun', ...
                 'Kategori','Satis_Kanali','Musteri_Tipi','Odeme_Yontemi'};
mevcut = opts.VariableNames;
for k = 1:numel(metinKolonlar)
    if ismember(metinKolonlar{k}, mevcut)
        opts = setvartype(opts, metinKolonlar{k}, 'string');
    end
end
data = readtable(dosyaAdi, opts);
nHam = height(data);
fprintf('Ham veri: %d satır, %d kolon\n', nHam, width(data));

%% 1) Musteri_ID silinir
if ismember('Musteri_ID', data.Properties.VariableNames)
    data.Musteri_ID = [];
end

%% 2) Siparis_ID tekrarları silinir
nOnce = height(data);
[~, idx] = unique(data.Siparis_ID, 'stable');
data = data(idx, :);
fprintf('Tekrar eden Siparis_ID silindi: %d  (kalan %d)\n', nOnce - height(data), height(data));

%% 3) Tarih: standart Gün.Ay.Yıl, geçersizler silinir
tarihHam = strip(erase(string(data.Tarih), ["'", """", "{", "}"]));
tarihTemiz = NaT(height(data), 1);
for i = 1:height(data)
    val = tarihHam(i);
    if ismissing(val) || val == "" || val == "<undefined>" || strcmpi(val, "nan") || strcmpi(val, "nat")
        continue;
    end
    parcalar = regexp(val, '[\.\-\/]', 'split');
    if numel(parcalar) ~= 3
        continue;
    end
    p1 = str2double(parcalar{1});
    p2 = str2double(parcalar{2});
    p3 = str2double(parcalar{3});
    if any(isnan([p1 p2 p3]))
        continue;
    end
    if p1 > 1000
        yil = p1; ay = p2; gun = p3;
    else
        gun = p1; ay = p2; yil = p3;
    end
    % MATLAB datetime taşır (31.06 → 01.07); takvim kontrolü şart
    if yil < 2000 || yil > 2035 || ay < 1 || ay > 12 || gun < 1
        continue;
    end
    sonGun = day(dateshift(datetime(yil, ay, 1), 'end', 'month'));
    if gun > sonGun
        continue;
    end
    tarihTemiz(i) = datetime(yil, ay, gun);
end
data = data(~isnat(tarihTemiz), :);
tarihTemiz = tarihTemiz(~isnat(tarihTemiz));
tarihTemiz.Format = 'dd.MM.yyyy';
data.Tarih = string(tarihTemiz);
fprintf('Geçersiz tarih silindi, kalan: %d\n', height(data));

%% 4) Metin kolonları standartlaştır
data.Sehir         = standartMetin(data.Sehir, sehirSozluk());
data.Bolge         = standartMetin(data.Bolge, bolgeSozluk());
data.Urun          = standartMetin(data.Urun, urunSozluk());
data.Kategori      = standartMetin(data.Kategori, kategoriSozluk());
data.Satis_Kanali  = standartMetin(data.Satis_Kanali, kanalSozluk());
data.Musteri_Tipi  = standartMetin(data.Musteri_Tipi, musteriSozluk());
data.Odeme_Yontemi = standartMetin(data.Odeme_Yontemi, odemeSozluk());

%% 5) Şehir-Bölge çapraz kontrol
sehirBolge = sehirBolgeHaritasi();
beklenenBolge = strings(height(data), 1);
for i = 1:height(data)
    if isKey(sehirBolge, data.Sehir(i))
        beklenenBolge(i) = sehirBolge(data.Sehir(i));
    else
        beklenenBolge(i) = missing;
    end
end
uyumsuz = ~ismissing(data.Sehir) & ~ismissing(data.Bolge) & (data.Bolge ~= beklenenBolge);
fprintf('Şehir-Bölge uyumsuz satır: %d\n', sum(uyumsuz));
data = data(~uyumsuz, :);

%% 6) Ürün-Kategori çapraz kontrol
urunKat = urunKategoriHaritasi();
beklenenKat = strings(height(data), 1);
for i = 1:height(data)
    if isKey(urunKat, data.Urun(i))
        beklenenKat(i) = urunKat(data.Urun(i));
    else
        beklenenKat(i) = missing;
    end
end
uyumsuzKat = ~ismissing(data.Urun) & ~ismissing(data.Kategori) & ...
             ~ismissing(beklenenKat) & (data.Kategori ~= beklenenKat);
fprintf('Ürün-Kategori uyumsuz satır: %d\n', sum(uyumsuzKat));
data = data(~uyumsuzKat, :);

%% 7) Eksik değer içeren satırlar silinir
eksik = false(height(data), 1);
for k = 1:width(data)
    col = data.(k);
    if isstring(col) || iscellstr(col) || iscategorical(col)
        s = string(col);
        eksik = eksik | ismissing(s) | s == "" | s == "<undefined>" | ...
                strcmpi(s, "nan") | strcmpi(s, "nat");
    else
        eksik = eksik | ismissing(col);
    end
end
fprintf('Eksik değerli satır: %d\n', sum(eksik));
data = data(~eksik, :);

%% 8) Sayısal mantıksal / gözlemsel uç değerler
data.Miktar = double(data.Miktar);
data.Birim_Fiyat_TL = double(data.Birim_Fiyat_TL);
data.Indirim_Orani = double(data.Indirim_Orani);
data.Birim_Maliyet_TL = double(data.Birim_Maliyet_TL);

data = data(data.Miktar >= 1, :);
q = quantile(data.Miktar, [0.25 0.75]);
iqrM = q(2) - q(1);
miktarUst = q(2) + 5 * iqrM;
data = data(data.Miktar <= miktarUst, :);

data = data(data.Indirim_Orani >= 0 & data.Indirim_Orani <= 1, :);
data = data(data.Indirim_Orani <= 0.50, :);
data = data(data.Birim_Fiyat_TL > 0 & data.Birim_Maliyet_TL > 0, :);

% Ürün medyanına göre fiyat / maliyet uçları
urunler = unique(data.Urun);
tut = true(height(data), 1);
for i = 1:numel(urunler)
    m = data.Urun == urunler(i);
    medF = median(data.Birim_Fiyat_TL(m));
    medM = median(data.Birim_Maliyet_TL(m));
    tut(m) = tut(m) & data.Birim_Fiyat_TL(m) <= 5 * medF & data.Birim_Fiyat_TL(m) >= 0.3 * medF;
    tut(m) = tut(m) & data.Birim_Maliyet_TL(m) <= 5 * medM & data.Birim_Maliyet_TL(m) >= 0.3 * medM;
end
data = data(tut, :);

%% 9) Fiyat-maliyet çapraz kontrol
oran = data.Birim_Maliyet_TL ./ data.Birim_Fiyat_TL;
mantikli = (data.Birim_Maliyet_TL < data.Birim_Fiyat_TL) & (oran >= 0.20) & (oran <= 0.95);
fprintf('Fiyat-maliyet mantık dışı: %d\n', sum(~mantikli));
data = data(mantikli, :);

%% 10) Hesaplanan kolonlar
data.Net_Satis = data.Miktar .* data.Birim_Fiyat_TL .* (1 - data.Indirim_Orani);
data.Toplam_Maliyet = data.Miktar .* data.Birim_Maliyet_TL;
data.Kar = data.Net_Satis - data.Toplam_Maliyet;
data.Kar_Marji = data.Kar ./ data.Net_Satis;

data.Net_Satis = round(data.Net_Satis, 2);
data.Toplam_Maliyet = round(data.Toplam_Maliyet, 2);
data.Kar = round(data.Kar, 2);
data.Kar_Marji = round(data.Kar_Marji, 6);

gecerliHesap = data.Net_Satis > 0 & isfinite(data.Kar_Marji) & abs(data.Kar_Marji) <= 0.95;
data = data(gecerliHesap, :);

%% 11) Kaydet
data = sortrows(data, 'Siparis_ID');
writetable(data, 'Temizlenmiş_SatışVerisi.xlsx');
save('data.mat', 'data');

fprintf('\n================ SONUÇ ================\n');
fprintf('Ham: %d  →  Temiz: %d  (silinen %d)\n', nHam, height(data), nHam - height(data));
fprintf('Kolonlar: %s\n', strjoin(data.Properties.VariableNames, ', '));
fprintf('Kayıt: Temizlenmiş_SatışVerisi.xlsx  ve  data.mat (değişken: data)\n');

%% -------- yerel fonksiyonlar --------
function out = standartMetin(s, sozluk)
    s = string(s);
    out = strings(size(s));
    for i = 1:numel(s)
        if ismissing(s(i)) || strtrim(s(i)) == ""
            out(i) = missing;
            continue;
        end
        anahtar = katmanAnahtar(s(i));
        if isKey(sozluk, anahtar)
            out(i) = sozluk(anahtar);
        else
            out(i) = missing;
        end
    end
end

function k = katmanAnahtar(s)
    k = strtrim(string(s));
    k = replace(k, ["İ", "I", "ı"], "i");
    k = lower(k);
    k = replace(k, "i̇", "i");
    k = regexprep(k, '[\s_\-]+', ' ');
end

function m = sehirSozluk()
    m = dictionary( ...
        ["istanbul","izmir","ankara","antalya","bursa", ...
         "adana","konya","gaziantep","samsun","trabzon"], ...
        ["İstanbul","İzmir","Ankara","Antalya","Bursa", ...
         "Adana","Konya","Gaziantep","Samsun","Trabzon"]);
end

function m = bolgeSozluk()
    m = dictionary( ...
        ["marmara","ege","akdeniz","ic anadolu","iç anadolu","karadeniz", ...
         "guneydogu anadolu","güneydoğu anadolu"], ...
        ["Marmara","Ege","Akdeniz","İç Anadolu","İç Anadolu","Karadeniz", ...
         "Güneydoğu Anadolu","Güneydoğu Anadolu"]);
end

function m = urunSozluk()
    m = dictionary( ...
        ["wireless mouse","desk lamp","monitor 27","monitor 24","notebook set", ...
         "usb c hub","usb-c hub","office chair","backpack","webcam", ...
         "mechanical keyboard","laptop stand","pen set"], ...
        ["Wireless Mouse","Desk Lamp","Monitor 27","Monitor 24","Notebook Set", ...
         "USB-C Hub","USB-C Hub","Office Chair","Backpack","Webcam", ...
         "Mechanical Keyboard","Laptop Stand","Pen Set"]);
end

function m = kategoriSozluk()
    m = dictionary( ...
        ["elektronik","ofis aksesuarlari","ofis aksesuarları","kirtasiye", ...
         "kırtasiye","mobilya","aksesuar"], ...
        ["Elektronik","Ofis Aksesuarları","Ofis Aksesuarları","Kırtasiye", ...
         "Kırtasiye","Mobilya","Aksesuar"]);
end

function m = kanalSozluk()
    m = dictionary(["online","magaza","mağaza","bayi"], ["Online","Mağaza","Mağaza","Bayi"]);
end

function m = musteriSozluk()
    m = dictionary(["bireysel","kobi","kurumsal"], ["Bireysel","KOBI","Kurumsal"]);
end

function m = odemeSozluk()
    m = dictionary( ...
        ["kredi karti","kredi kartı","havale/eft","havale eft","nakit"], ...
        ["Kredi Kartı","Kredi Kartı","Havale/EFT","Havale/EFT","Nakit"]);
end

function m = sehirBolgeHaritasi()
    m = dictionary( ...
        ["İstanbul","Bursa","İzmir","Ankara","Konya","Antalya","Adana", ...
         "Samsun","Trabzon","Gaziantep"], ...
        ["Marmara","Marmara","Ege","İç Anadolu","İç Anadolu","Akdeniz","Akdeniz", ...
         "Karadeniz","Karadeniz","Güneydoğu Anadolu"]);
end

function m = urunKategoriHaritasi()
    m = dictionary( ...
        ["Wireless Mouse","USB-C Hub","Webcam","Monitor 24","Monitor 27", ...
         "Mechanical Keyboard","Desk Lamp","Laptop Stand","Office Chair", ...
         "Notebook Set","Pen Set","Backpack"], ...
        ["Elektronik","Elektronik","Elektronik","Elektronik","Elektronik", ...
         "Elektronik","Ofis Aksesuarları","Ofis Aksesuarları","Mobilya", ...
         "Kırtasiye","Kırtasiye","Aksesuar"]);
end
