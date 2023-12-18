//
// Check input samplesheet and get read channels
//

include { UNTAR as UNTAR_COMPRESSED_INPUT } from "../../modules/nf-core/untar"

workflow INPUT_CHECK {

    take:
    samplesheet // file: /path/to/samplesheet.csv

    main:
    ch_st = Channel.from(samplesheet)
        .splitCsv ( header: true, sep: ',')
        .branch   {
            spaceranger: !it.containsKey("spaceranger_dir")
            downstream: it.containsKey("spaceranger_dir")
        }

    // Pre-Space Ranger analysis: create meta map and check input existance
    ch_spaceranger_input = ch_st.spaceranger.map { create_channel_spaceranger(it) }

    // Post-Space Ranger analysis:
    // Check if running the `test` profile, which uses a tarball of the testdata
    if ( workflow.profile.contains('test') ) {

        // Untar Space Ranger output stored as tarball
        ch_downstream_tar = ch_st.downstream.map { create_channel_downstream_tar(it) }
        UNTAR_COMPRESSED_INPUT (
            ch_downstream_tar
        )

        // Create meta map corresponding to non-tarballed input
        ch_downstream = UNTAR_COMPRESSED_INPUT.out.untar
            .map { meta, dir -> [sample: meta.id, spaceranger_dir: dir] }

    } else {

        // Non-tarballed input data
        ch_downstream = ch_st.downstream

    }

    // Create meta map and check input existance
    ch_downstream_input = ch_downstream.map { create_channel_downstream(it) }

    emit:
    ch_spaceranger_input                      // channel: [ val(meta), [ st data ] ]
    ch_downstream_input                       // channel: [ val(meta), [ st data ] ]
}

// Function to get list of [ meta, [ spaceranger_dir ]]
def create_channel_downstream_tar(LinkedHashMap meta) {
    meta['id'] = meta.remove('sample')
    spaceranger_dir = meta.remove('spaceranger_dir')
    return [meta, spaceranger_dir]
}

// Function to get list of [ meta, [ raw_feature_bc_matrix, tissue_positions,
//                                   scalefactors, hires_image, lowres_image ]]
def create_channel_downstream(LinkedHashMap meta) {
    meta["id"] = meta.remove("sample")
    spaceranger_dir = file("${meta.remove('spaceranger_dir')}/**")
    for (f in Utils.DOWNSTREAM_REQUIRED_SPACERANGER_FILES) {
        if(!spaceranger_dir*.name.contains(f)) {
            error "The specified spaceranger output directory doesn't contain the required file `${f}` for sample `${meta.id}`"
        }
    }
    return [meta, spaceranger_dir]
}

// Function to get list of [ meta, [ fastq_dir, tissue_hires_image, slide, area ]]
def create_channel_spaceranger(LinkedHashMap meta) {
    meta["id"] = meta.remove("sample")

    // Convert a path in `meta` to a file object and return it. If `key` is not contained in `meta`
    // return an empty list which is recognized as 'no file' by nextflow.
    def get_file_from_meta = {key ->
         v = meta.remove(key);
         return v ? file(v) : []
    }

    fastq_dir = meta.remove("fastq_dir")
    fastq_files = file("${fastq_dir}/${meta['id']}*.fastq.gz")
    manual_alignment = get_file_from_meta("manual_alignment")
    slidefile = get_file_from_meta("slidefile")
    image = get_file_from_meta("image")
    cytaimage = get_file_from_meta("cytaimage")
    colorizedimage = get_file_from_meta("colorizedimage")
    darkimage = get_file_from_meta("darkimage")

    if(!fastq_files.size()) {
        error "No `fastq_dir` specified or no samples found in folder."
    } else {
        log.info "${fastq_files.size()} FASTQ files found for sample ${meta['id']}."
    }

    check_optional_files = ["manual_alignment", "slidefile", "image", "cytaimage", "colorizedimage", "darkimage"]
    for(k in check_optional_files) {
        if(this.binding[k] && !this.binding[k].exists()) {
            error "File for `${k}` is specified, but does not exist: ${this.binding[k]}."
        }
    }
    if(!(image || cytaimage || colorizedimage || darkimage)) {
        error "Need to specify at least one of 'image', 'cytaimage', 'colorizedimage', or 'darkimage' in the samplesheet"
    }

    return [meta, fastq_files, image, cytaimage, darkimage, colorizedimage, manual_alignment, slidefile]
}

