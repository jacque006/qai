-- QAI pass-through hook (skeleton).
-- Wraps the global AddGlobalBaseTemplate and calls the original unchanged.
-- Behavior is identical to stock LOUD. This file only proves that the hook loads.

local QAI_original_AddGlobalBaseTemplate = AddGlobalBaseTemplate

if QAI_original_AddGlobalBaseTemplate then
    LOG('QAI: hook loaded; base AddGlobalBaseTemplate found, passing through unchanged')
else
    LOG('QAI: hook loaded; base AddGlobalBaseTemplate NOT found at hook time (load-order problem)')
end

function AddGlobalBaseTemplate(aiBrain, locationType, baseBuilderName)
    if QAI_original_AddGlobalBaseTemplate then
        return QAI_original_AddGlobalBaseTemplate(aiBrain, locationType, baseBuilderName)
    end
end
