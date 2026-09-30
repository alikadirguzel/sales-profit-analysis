function [data, sourceFile] = loadAnalysisData(optionalPath)
%LOADANALYSISDATA  Load cleaned sales data from Excel, CSV, or MAT.
%
%   Column names are preserved (VariableNamingRule = 'preserve').
%   No renaming is applied. Downstream code reads the names that exist
%   in the file rather than assuming a fixed schema.

    if nargin < 1
        optionalPath = '';
    end

    cands = {};
    if ~isempty(optionalPath)
        cands{end+1} = optionalPath; %#ok<AGROW>
    end

    cands = [cands, { ...
        'Temizlenmis_SatisVerisi.xlsx', ...
        'Temizlenmiş_SatışVerisi.xlsx', ...
        'data.mat', ...
        'Temizlenmis_SatisVerisi.csv', ...
        'Temizlenmiş_SatışVerisi.csv'}];

    extra = [dir('*.xlsx'); dir('*.csv'); dir('*.mat')];
    for i = 1:numel(extra)
        cands{end+1} = extra(i).name; %#ok<AGROW>
    end
    cands = unique(cands, 'stable');

    for i = 1:numel(cands)
        f = cands{i};
        if isempty(f) || ~isfile(f)
            continue;
        end
        try
            data = readOneTable(f);
            sourceFile = f;
            fprintf('Data loaded: %s  (%d rows, %d columns)\n', ...
                f, height(data), width(data));
            return;
        catch ME
            fprintf('Skipped %s (%s)\n', f, ME.message);
        end
    end

    error('loadAnalysisData:NotFound', [ ...
        'No readable data file found. Expected Excel/CSV/MAT ' ...
        '(e.g. Temizlenmis_SatisVerisi.xlsx). Run temizle_satis_verisi.m first.']);
end

function data = readOneTable(f)
    [~, ~, ext] = fileparts(f);
    ext = lower(ext);
    switch ext
        case {'.xlsx', '.xls', '.csv'}
            opts = detectImportOptions(f, 'VariableNamingRule', 'preserve');
            data = readtable(f, opts);
        case '.mat'
            s = load(f);
            if isfield(s, 'data') && istable(s.data)
                data = s.data;
            else
                fn = fieldnames(s);
                data = [];
                for i = 1:numel(fn)
                    if istable(s.(fn{i}))
                        data = s.(fn{i});
                        break;
                    end
                end
                if isempty(data)
                    error('MAT file has no table.');
                end
            end
        otherwise
            error('Unsupported extension: %s', ext);
    end
    if height(data) < 1 || width(data) < 2
        error('Table is empty or has too few columns.');
    end
end
