%% Sales data cleaning
% Original Turkish headers are renamed to English.
% Output table: data
% Excel output (this folder): cleaned_sales_data.xlsx

clc; clear; close all;

%% 0) Read raw file and rename Turkish headers if present
fileName = 'raw_sales_data.xlsx';
if ~isfile(fileName) && isfile('SatışVerisi.xlsx')
    fileName = 'SatışVerisi.xlsx';
end
opts = detectImportOptions(fileName, 'VariableNamingRule', 'preserve');
textColsTr = {'Siparis_ID','Tarih','Musteri_ID','Sehir','Bolge','Urun', ...
              'Kategori','Satis_Kanali','Musteri_Tipi','Odeme_Yontemi'};
textColsEn = {'Order_ID','Date','Customer_ID','City','Region','Product', ...
              'Category','Sales_Channel','Customer_Type','Payment_Method'};
present = opts.VariableNames;
for k = 1:numel(textColsTr)
    if ismember(textColsTr{k}, present)
        opts = setvartype(opts, textColsTr{k}, 'string');
    end
end
for k = 1:numel(textColsEn)
    if ismember(textColsEn{k}, present)
        opts = setvartype(opts, textColsEn{k}, 'string');
    end
end
data = readtable(fileName, opts);
data = renameTurkishColumns(data);
nRaw = height(data);
fprintf('Raw data: %d rows, %d columns\n', nRaw, width(data));

%% 1) Drop Customer_ID
if ismember('Customer_ID', data.Properties.VariableNames)
    data.Customer_ID = [];
end

%% 2) Drop duplicate Order_ID
nBefore = height(data);
[~, idx] = unique(data.Order_ID, 'stable');
data = data(idx, :);
fprintf('Duplicate Order_ID removed: %d  (remaining %d)\n', nBefore - height(data), height(data));

%% 3) Date: keep valid calendar dates as dd.MM.yyyy
rawDate = strip(erase(string(data.Date), ["'", """", "{", "}"]));
cleanDate = NaT(height(data), 1);
for i = 1:height(data)
    val = rawDate(i);
    if ismissing(val) || val == "" || val == "<undefined>" || strcmpi(val, "nan") || strcmpi(val, "nat")
        continue;
    end
    parts = regexp(val, '[\.\-\/]', 'split');
    if numel(parts) ~= 3
        continue;
    end
    p1 = str2double(parts{1});
    p2 = str2double(parts{2});
    p3 = str2double(parts{3});
    if any(isnan([p1 p2 p3]))
        continue;
    end
    if p1 > 1000
        yearV = p1; monthV = p2; dayV = p3;
    else
        dayV = p1; monthV = p2; yearV = p3;
    end
    if yearV < 2000 || yearV > 2035 || monthV < 1 || monthV > 12 || dayV < 1
        continue;
    end
    lastDay = day(dateshift(datetime(yearV, monthV, 1), 'end', 'month'));
    if dayV > lastDay
        continue;
    end
    cleanDate(i) = datetime(yearV, monthV, dayV);
end
data = data(~isnat(cleanDate), :);
cleanDate = cleanDate(~isnat(cleanDate));
cleanDate.Format = 'dd.MM.yyyy';
data.Date = string(cleanDate);
fprintf('Invalid dates removed, remaining: %d\n', height(data));

%% 4) Standardize text columns
data.City = standardizeText(data.City, cityDict());
data.Region = standardizeText(data.Region, regionDict());
data.Product = standardizeText(data.Product, productDict());
data.Category = standardizeText(data.Category, categoryDict());
data.Sales_Channel = standardizeText(data.Sales_Channel, channelDict());
data.Customer_Type = standardizeText(data.Customer_Type, customerDict());
data.Payment_Method = standardizeText(data.Payment_Method, paymentDict());

%% 5) City-Region cross-check
cityRegion = cityRegionMap();
expectedRegion = strings(height(data), 1);
for i = 1:height(data)
    if isKey(cityRegion, data.City(i))
        expectedRegion(i) = cityRegion(data.City(i));
    else
        expectedRegion(i) = missing;
    end
end
mismatch = ~ismissing(data.City) & ~ismissing(data.Region) & (data.Region ~= expectedRegion);
fprintf('City-Region mismatched rows: %d\n', sum(mismatch));
data = data(~mismatch, :);

%% 6) Product-Category cross-check
prodCat = productCategoryMap();
expectedCat = strings(height(data), 1);
for i = 1:height(data)
    if isKey(prodCat, data.Product(i))
        expectedCat(i) = prodCat(data.Product(i));
    else
        expectedCat(i) = missing;
    end
end
mismatchCat = ~ismissing(data.Product) & ~ismissing(data.Category) & ...
             ~ismissing(expectedCat) & (data.Category ~= expectedCat);
fprintf('Product-Category mismatched rows: %d\n', sum(mismatchCat));
data = data(~mismatchCat, :);

%% 7) Drop rows with missing values
missingRow = false(height(data), 1);
for k = 1:width(data)
    col = data.(k);
    if isstring(col) || iscellstr(col) || iscategorical(col)
        s = string(col);
        missingRow = missingRow | ismissing(s) | s == "" | s == "<undefined>" | ...
                strcmpi(s, "nan") | strcmpi(s, "nat");
    else
        missingRow = missingRow | ismissing(col);
    end
end
fprintf('Rows with missing values: %d\n', sum(missingRow));
data = data(~missingRow, :);

%% 8) Numeric sanity / observational outliers
data.Quantity = double(data.Quantity);
data.Unit_Price_TL = double(data.Unit_Price_TL);
data.Discount_Rate = double(data.Discount_Rate);
data.Unit_Cost_TL = double(data.Unit_Cost_TL);

data = data(data.Quantity >= 1, :);
q = quantile(data.Quantity, [0.25 0.75]);
iqrM = q(2) - q(1);
qtyCap = q(2) + 5 * iqrM;
data = data(data.Quantity <= qtyCap, :);

data = data(data.Discount_Rate >= 0 & data.Discount_Rate <= 1, :);
data = data(data.Discount_Rate <= 0.50, :);
data = data(data.Unit_Price_TL > 0 & data.Unit_Cost_TL > 0, :);

products = unique(data.Product);
keep = true(height(data), 1);
for i = 1:numel(products)
    m = data.Product == products(i);
    medF = median(data.Unit_Price_TL(m));
    medM = median(data.Unit_Cost_TL(m));
    keep(m) = keep(m) & data.Unit_Price_TL(m) <= 5 * medF & data.Unit_Price_TL(m) >= 0.3 * medF;
    keep(m) = keep(m) & data.Unit_Cost_TL(m) <= 5 * medM & data.Unit_Cost_TL(m) >= 0.3 * medM;
end
data = data(keep, :);

%% 9) Price-cost cross-check
ratio = data.Unit_Cost_TL ./ data.Unit_Price_TL;
plausible = (data.Unit_Cost_TL < data.Unit_Price_TL) & (ratio >= 0.20) & (ratio <= 0.95);
fprintf('Implausible price-cost rows: %d\n', sum(~plausible));
data = data(plausible, :);

%% 10) Derived columns
data.Net_Sales = data.Quantity .* data.Unit_Price_TL .* (1 - data.Discount_Rate);
data.Total_Cost = data.Quantity .* data.Unit_Cost_TL;
data.Profit = data.Net_Sales - data.Total_Cost;
data.Profit_Margin = data.Profit ./ data.Net_Sales;

data.Net_Sales = round(data.Net_Sales, 2);
data.Total_Cost = round(data.Total_Cost, 2);
data.Profit = round(data.Profit, 2);
data.Profit_Margin = round(data.Profit_Margin, 6);

validCalc = data.Net_Sales > 0 & isfinite(data.Profit_Margin) & abs(data.Profit_Margin) <= 0.95;
data = data(validCalc, :);

%% 11) Save
data = sortrows(data, 'Order_ID');
writetable(data, 'cleaned_sales_data.xlsx');
save('data.mat', 'data');

fprintf('\n================ RESULT ================\n');
fprintf('Raw: %d  ->  Clean: %d  (dropped %d)\n', nRaw, height(data), nRaw - height(data));
fprintf('Columns: %s\n', strjoin(data.Properties.VariableNames, ', '));
fprintf('Saved: cleaned_sales_data.xlsx and data.mat (variable: data)\n');

%% -------- local functions --------
function out = standardizeText(s, dict)
    s = string(s);
    out = strings(size(s));
    for i = 1:numel(s)
        if ismissing(s(i)) || strtrim(s(i)) == ""
            out(i) = missing;
            continue;
        end
        key = foldKey(s(i));
        if isKey(dict, key)
            out(i) = dict(key);
        else
            out(i) = missing;
        end
    end
end

function k = foldKey(s)
    k = strtrim(string(s));
    k = replace(k, ["İ", "I", "ı"], "i");
    k = lower(k);
    k = replace(k, "i̇", "i");
    k = regexprep(k, '[\s_\-]+', ' ');
end

function m = cityDict()
    m = dictionary( ...
        ["istanbul","izmir","ankara","antalya","bursa", ...
         "adana","konya","gaziantep","samsun","trabzon"], ...
        ["Istanbul","Izmir","Ankara","Antalya","Bursa", ...
         "Adana","Konya","Gaziantep","Samsun","Trabzon"]);
end

function m = regionDict()
    m = dictionary( ...
        ["marmara","ege","akdeniz","ic anadolu","iç anadolu","karadeniz", ...
         "guneydogu anadolu","güneydoğu anadolu"], ...
        ["Marmara","Aegean","Mediterranean","Central Anatolia","Central Anatolia","Black Sea", ...
         "Southeastern Anatolia","Southeastern Anatolia"]);
end

function m = productDict()
    m = dictionary( ...
        ["wireless mouse","desk lamp","monitor 27","monitor 24","notebook set", ...
         "usb c hub","usb-c hub","office chair","backpack","webcam", ...
         "mechanical keyboard","laptop stand","pen set"], ...
        ["Wireless Mouse","Desk Lamp","Monitor 27","Monitor 24","Notebook Set", ...
         "USB-C Hub","USB-C Hub","Office Chair","Backpack","Webcam", ...
         "Mechanical Keyboard","Laptop Stand","Pen Set"]);
end

function m = categoryDict()
    m = dictionary( ...
        ["elektronik","ofis aksesuarlari","ofis aksesuarları","kirtasiye", ...
         "kırtasiye","mobilya","aksesuar"], ...
        ["Electronics","Office Accessories","Office Accessories","Stationery", ...
         "Stationery","Furniture","Accessories"]);
end

function m = channelDict()
    m = dictionary(["online","magaza","mağaza","bayi"], ["Online","Store","Store","Dealer"]);
end

function m = customerDict()
    m = dictionary(["bireysel","kobi","kurumsal"], ["Individual","SME","Corporate"]);
end

function m = paymentDict()
    m = dictionary( ...
        ["kredi karti","credit card","havale/eft","havale eft","nakit","cash"], ...
        ["Credit Card","Credit Card","Bank Transfer","Bank Transfer","Cash","Cash"]);
end

function m = cityRegionMap()
    m = dictionary( ...
        ["Istanbul","Bursa","Izmir","Ankara","Konya","Antalya","Adana", ...
         "Samsun","Trabzon","Gaziantep"], ...
        ["Marmara","Marmara","Aegean","Central Anatolia","Central Anatolia","Mediterranean","Mediterranean", ...
         "Black Sea","Black Sea","Southeastern Anatolia"]);
end

function m = productCategoryMap()
    m = dictionary( ...
        ["Wireless Mouse","USB-C Hub","Webcam","Monitor 24","Monitor 27", ...
         "Mechanical Keyboard","Desk Lamp","Laptop Stand","Office Chair", ...
         "Notebook Set","Pen Set","Backpack"], ...
        ["Electronics","Electronics","Electronics","Electronics","Electronics", ...
         "Electronics","Office Accessories","Office Accessories","Furniture", ...
         "Stationery","Stationery","Accessories"]);
end

function data = renameTurkishColumns(data)
    pairs = { ...
        'Siparis_ID','Order_ID'; 'Tarih','Date'; 'Musteri_ID','Customer_ID'; ...
        'Sehir','City'; 'Bolge','Region'; 'Urun','Product'; 'Kategori','Category'; ...
        'Satis_Kanali','Sales_Channel'; 'Musteri_Tipi','Customer_Type'; ...
        'Odeme_Yontemi','Payment_Method'; 'Miktar','Quantity'; ...
        'Birim_Fiyat_TL','Unit_Price_TL'; 'Indirim_Orani','Discount_Rate'; ...
        'Birim_Maliyet_TL','Unit_Cost_TL'; 'Net_Satis','Net_Sales'; ...
        'Toplam_Maliyet','Total_Cost'; 'Kar','Profit'; 'Kar_Marji','Profit_Margin'};
    names = data.Properties.VariableNames;
    for i = 1:size(pairs, 1)
        old = pairs{i, 1};
        new = pairs{i, 2};
        idx = find(strcmp(names, old), 1);
        if ~isempty(idx)
            names{idx} = new;
        end
    end
    data.Properties.VariableNames = names;
end
